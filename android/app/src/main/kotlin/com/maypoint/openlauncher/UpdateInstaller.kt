package com.maypoint.openlauncher

import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageInfo
import android.content.pm.PackageInstaller
import android.content.pm.PackageInstaller.SessionParams
import android.content.pm.PackageManager
import android.os.Build
import java.io.File
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.withTimeoutOrNull

/**
 * Installs a downloaded update of this app with the TV's own installer,
 * which decides whether to ask the user first.
 */
class UpdateInstaller(private val context: Context) {
    /** Only returns if the update was not installed, with why. */
    suspend fun run(path: String): String {
        val apk = File(path)
        refusal(apk)?.let { return it }
        val installer = context.packageManager.packageInstaller
        val params = SessionParams(SessionParams.MODE_FULL_INSTALL).apply {
            setAppPackageName(context.packageName)
            setSize(apk.length())
            // An app updating itself may be spared the question.
            if (Build.VERSION.SDK_INT >= 31) {
                setRequireUserAction(SessionParams.USER_ACTION_NOT_REQUIRED)
            }
        }
        val answer = CompletableDeferred<String>()
        UpdateReceiver.onStatus = { heard(it, answer) }
        var session: Int? = null
        try {
            val id = installer.createSession(params).also { session = it }
            installer.openSession(id).use { open ->
                open.openWrite("update.apk", 0, apk.length()).use { out ->
                    apk.inputStream().use { it.copyTo(out) }
                    open.fsync(out)
                }
                relaunchAfter(true)
                open.commit(UpdateReceiver.sender(context, id))
            }
            return withTimeoutOrNull(WAIT_MS) { answer.await() }
                ?: "The TV did not finish installing it."
        } catch (e: Exception) {
            return e.message ?: e.javaClass.simpleName
        } finally {
            // Only reached when it was not installed.
            UpdateReceiver.onStatus = null
            relaunchAfter(false)
            session?.let { runCatching { installer.abandonSession(it) } }
        }
    }

    private fun heard(said: Intent, answer: CompletableDeferred<String>) {
        when (said.getIntExtra(PackageInstaller.EXTRA_STATUS, PackageInstaller.STATUS_FAILURE)) {
            PackageInstaller.STATUS_PENDING_USER_ACTION -> {
                val ask = if (Build.VERSION.SDK_INT >= 33) {
                    said.getParcelableExtra(Intent.EXTRA_INTENT, Intent::class.java)
                } else {
                    @Suppress("DEPRECATION")
                    said.getParcelableExtra(Intent.EXTRA_INTENT)
                }
                runCatching {
                    context.startActivity(ask!!.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                }.onFailure { answer.complete("The TV could not ask to install it.") }
            }
            // The install ends this process before it is heard.
            PackageInstaller.STATUS_SUCCESS -> Unit
            PackageInstaller.STATUS_FAILURE_ABORTED ->
                answer.complete("It was cancelled on the TV.")
            else -> answer.complete(
                said.getStringExtra(PackageInstaller.EXTRA_STATUS_MESSAGE)
                    ?: "The TV did not install it.",
            )
        }
    }

    private fun relaunchAfter(wanted: Boolean) = prefs(context).edit().apply {
        if (wanted) putLong(RELAUNCH_UNTIL, System.currentTimeMillis() + WAIT_MS)
        else remove(RELAUNCH_UNTIL)
    }.apply()

    /**
     * Why [apk] is not an update of this app, or null. Nothing but a newer
     * copy of this app is handed over; the TV itself then refuses one signed
     * with another key.
     */
    private fun refusal(apk: File): String? {
        val pm = context.packageManager
        val update = pm.getPackageArchiveInfo(apk.path, SIGNERS)
            ?: return "The download is not an app."
        if (update.packageName != context.packageName) {
            return "The download is not OpenLauncher."
        }
        val own = pm.getPackageInfo(context.packageName, SIGNERS)
        if (versionCode(update) <= versionCode(own)) {
            return "The download is not newer than what is installed."
        }
        val signers = signers(update)
        // Some Android versions do not read an APK file's signers.
        if (signers.isNotEmpty() && signers != signers(own)) {
            return "The download is not signed by OpenLauncher."
        }
        return null
    }

    private fun versionCode(info: PackageInfo): Long =
        if (Build.VERSION.SDK_INT >= 28) info.longVersionCode else {
            @Suppress("DEPRECATION")
            info.versionCode.toLong()
        }

    private fun signers(info: PackageInfo): Set<String> {
        val signatures = if (Build.VERSION.SDK_INT >= 28) {
            info.signingInfo?.apkContentsSigners
        } else {
            @Suppress("DEPRECATION")
            info.signatures
        }
        return signatures.orEmpty().map { it.toCharsString() }.toSet()
    }

    companion object {
        private const val WAIT_MS = 5 * 60 * 1000L
        private const val RELAUNCH_UNTIL = "relaunchUntil"

        @Suppress("DEPRECATION")
        private val SIGNERS = if (Build.VERSION.SDK_INT >= 28) {
            PackageManager.GET_SIGNING_CERTIFICATES
        } else {
            PackageManager.GET_SIGNATURES
        }

        private fun prefs(context: Context) =
            context.getSharedPreferences("updates", Context.MODE_PRIVATE)

        /** Whether an update has just replaced the app, with the launcher to be opened again. */
        fun justUpdated(context: Context) =
            System.currentTimeMillis() < prefs(context).getLong(RELAUNCH_UNTIL, 0)

        /** The launcher is back in front. */
        fun relaunched(context: Context) {
            if (prefs(context).contains(RELAUNCH_UNTIL)) {
                prefs(context).edit().remove(RELAUNCH_UNTIL).apply()
            }
        }
    }
}

/** Hears how an install went, and that an update has replaced this app. */
class UpdateReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            ACTION_STATUS -> onStatus?.invoke(intent)
            // Android only lets this through from the background on some
            // versions; elsewhere HomeButtonService opens the launcher.
            Intent.ACTION_MY_PACKAGE_REPLACED -> if (UpdateInstaller.justUpdated(context)) {
                runCatching {
                    context.startActivity(
                        Intent(context, MainActivity::class.java)
                            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
                    )
                }
            }
        }
    }

    companion object {
        private const val ACTION_STATUS = "com.maypoint.openlauncher.UPDATE_STATUS"

        /** Set while an install is under way. */
        var onStatus: ((Intent) -> Unit)? = null

        fun sender(context: Context, session: Int) = PendingIntent.getBroadcast(
            context,
            session,
            Intent(context, UpdateReceiver::class.java).setAction(ACTION_STATUS),
            // Mutable: the installer adds the status to it.
            PendingIntent.FLAG_UPDATE_CURRENT or
                if (Build.VERSION.SDK_INT >= 31) PendingIntent.FLAG_MUTABLE else 0,
        ).intentSender
    }
}
