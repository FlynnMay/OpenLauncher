package com.maypoint.openlauncher

import android.Manifest
import android.accessibilityservice.AccessibilityService
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.SystemClock
import android.provider.Settings
import android.view.KeyEvent
import android.view.accessibility.AccessibilityEvent
import kotlinx.coroutines.delay

/**
 * Makes the remote's Home button open OpenLauncher.
 *
 * Google TV has no setting for choosing the home app, so the Home key is
 * caught here before the system sends it to the stock launcher. Not every TV
 * hands that key to accessibility services, so as a second line the stock
 * home screen is replaced whenever it comes to the front.
 */
class HomeButtonService : AccessibilityService() {
    // The activity the system opens for Home, e.g. Google TV's home screen.
    private var stockHome: ComponentName? = null

    override fun onServiceConnected() {
        connected = true
        val home = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_HOME)
        val info = packageManager
            .resolveActivity(home, PackageManager.MATCH_DEFAULT_ONLY)?.activityInfo
        // "android" is the system's chooser, shown when no home app is preferred.
        stockHome = info
            ?.takeIf { it.packageName != packageName && it.packageName != "android" }
            ?.let { ComponentName(it.packageName, it.name) }

        // At boot the stock home screen is usually up before this service is,
        // so its arrival is never seen. Take over straight away instead.
        if (SystemClock.elapsedRealtime() < BOOT_WINDOW_MS) showLauncher()
    }

    override fun onKeyEvent(event: KeyEvent): Boolean {
        if (event.keyCode != KeyEvent.KEYCODE_HOME) return false
        if (event.action == KeyEvent.ACTION_UP) showLauncher()
        // Swallow both down and up so the stock launcher never sees the press.
        return true
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        val stock = stockHome ?: return
        if (event?.eventType == AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED &&
            event.packageName?.toString() == stock.packageName &&
            event.className?.toString() == stock.className
        ) {
            showLauncher()
        }
    }

    override fun onDestroy() {
        connected = false
        super.onDestroy()
    }

    private fun showLauncher() {
        startActivity(
            Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
        )
    }

    override fun onInterrupt() = Unit

    companion object {
        // How long after power-on a starting service is taken to be part of boot.
        private const val BOOT_WINDOW_MS = 3 * 60 * 1000L

        /** Whether the system has actually started the service in this process. */
        @Volatile
        var connected = false
            private set

        /**
         * Some TVs refuse to start the service at boot even though it is
         * switched on, and never try again by themselves. Switching it off and
         * on while the app is running makes the system retry. Returns whether
         * a retry was made.
         */
        suspend fun reconnectIfStuck(context: Context): Boolean {
            if (connected || !isEnabled(context) || !canManage(context)) return false
            setEnabled(context, false)
            delay(RETRY_SETTLE_MS)
            setEnabled(context, true)
            return true
        }

        private const val RETRY_SETTLE_MS = 300L

        /**
         * Whether this service is switched on in the TV's settings. Only the
         * list is consulted: the separate "accessibility enabled" flag is
         * cleared by the system whenever no service is running, which is
         * exactly the stuck state [reconnectIfStuck] has to recognise.
         */
        fun isEnabled(context: Context): Boolean {
            val me = ComponentName(context, HomeButtonService::class.java)
            val enabled = Settings.Secure.getString(
                context.contentResolver,
                Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES,
            ).orEmpty()
            return enabled.split(':').any { ComponentName.unflattenFromString(it) == me }
        }

        /** Whether this app may change the setting itself (granted over ADB). */
        fun canManage(context: Context) =
            context.checkSelfPermission(Manifest.permission.WRITE_SECURE_SETTINGS) ==
                PackageManager.PERMISSION_GRANTED

        /** Switches the service on or off, leaving other accessibility services alone. */
        fun setEnabled(context: Context, enabled: Boolean) {
            if (!canManage(context)) {
                throw FlutterError("needs-setup", "Run automatic setup first")
            }
            val resolver = context.contentResolver
            val me = ComponentName(context, HomeButtonService::class.java)
            val others = Settings.Secure
                .getString(resolver, Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES)
                .orEmpty()
                .split(':')
                .filter { it.isNotBlank() && ComponentName.unflattenFromString(it) != me }
            val services = if (enabled) others + me.flattenToString() else others
            Settings.Secure.putString(
                resolver,
                Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES,
                services.joinToString(":"),
            )
            if (enabled) {
                Settings.Secure.putInt(resolver, Settings.Secure.ACCESSIBILITY_ENABLED, 1)
            }
        }

        /**
         * Opens the screen where the service is switched on. Some TVs stub out
         * the accessibility settings intent, so fall back to the main settings.
         */
        fun openSettings(context: Context) {
            val pm = context.packageManager
            val intent = listOf(Settings.ACTION_ACCESSIBILITY_SETTINGS, Settings.ACTION_SETTINGS)
                .map { Intent(it).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK) }
                .firstOrNull { candidate ->
                    val target = pm.resolveActivity(candidate, 0)?.activityInfo?.packageName
                    target != null && !target.endsWith(".frameworkpackagestubs")
                }
                ?: throw FlutterError("no-settings", "This device has no settings screen to open")
            context.startActivity(intent)
        }
    }
}
