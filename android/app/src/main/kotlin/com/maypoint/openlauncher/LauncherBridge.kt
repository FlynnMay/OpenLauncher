package com.maypoint.openlauncher

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.content.pm.ResolveInfo
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.Drawable
import android.os.Build
import io.flutter.plugin.common.BinaryMessenger
import java.io.File
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext

/** Android side of the Pigeon bridge: installed apps, TV inputs, artwork, launching. */
class LauncherBridge(
    private val context: Context,
    messenger: BinaryMessenger,
) : LauncherHostApi {
    private val flutterApi = LauncherFlutterApi(messenger)
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private val iconDir = File(context.cacheDir, "icons")

    // Package broadcasts arrive in bursts, so queries can overlap; an older one
    // must not prune artwork a newer one just wrote.
    private val queryLock = Mutex()

    private val inputs = TvInputSource(context) {
        scope.launch { runCatching { flutterApi.onInputsChanged() } }
    }

    private val packageReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            scope.launch { runCatching { flutterApi.onAppsChanged() } }
        }
    }

    init {
        val filter = IntentFilter().apply {
            addAction(Intent.ACTION_PACKAGE_ADDED)
            addAction(Intent.ACTION_PACKAGE_REMOVED)
            addAction(Intent.ACTION_PACKAGE_CHANGED)
            addAction(Intent.ACTION_PACKAGE_REPLACED)
            addDataScheme("package")
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            context.registerReceiver(packageReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            context.registerReceiver(packageReceiver, filter)
        }
    }

    /**
     * Called when the launcher comes to the front. Waits first, so a service
     * the system is still starting is not mistaken for a stuck one.
     */
    fun checkHomeButton() {
        scope.launch {
            delay(HOME_BUTTON_CHECK_DELAY_MS)
            runCatching { HomeButtonService.reconnectIfStuck(context) }
        }
    }

    fun dispose() {
        context.unregisterReceiver(packageReceiver)
        inputs.dispose()
        scope.cancel()
    }

    override suspend fun listApps(): List<InstalledApp> =
        withContext(Dispatchers.IO) { queryLock.withLock { queryApps() } }

    override fun launchApp(packageName: String) {
        val pm = context.packageManager
        val intent = pm.getLeanbackLaunchIntentForPackage(packageName)
            ?: pm.getLaunchIntentForPackage(packageName)
            ?: throw FlutterError("not-launchable", "No launch intent for $packageName")
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        context.startActivity(intent)
    }

    override suspend fun listInputs(): List<TvInput> =
        withContext(Dispatchers.IO) { inputs.list() }

    override fun switchToInput(inputId: String) = inputs.switchTo(inputId)

    override fun isHomeButtonEnabled() = HomeButtonService.isEnabled(context)

    override fun openHomeButtonSettings() = HomeButtonService.openSettings(context)

    override fun canManageHomeButton() = HomeButtonService.canManage(context)

    override fun setHomeButtonEnabled(enabled: Boolean) =
        HomeButtonService.setEnabled(context, enabled)

    override suspend fun runAutomaticSetup(): SetupResult =
        withContext(Dispatchers.IO) { DeviceSetup(context).run() }

    private fun queryApps(): List<InstalledApp> {
        val pm = context.packageManager
        // TV apps first so their entry wins over the same package's phone entry.
        val entries = LinkedHashMap<String, ResolveInfo>()
        for (category in listOf(Intent.CATEGORY_LEANBACK_LAUNCHER, Intent.CATEGORY_LAUNCHER)) {
            val intent = Intent(Intent.ACTION_MAIN).addCategory(category)
            for (info in pm.queryIntentActivities(intent, 0)) {
                entries.putIfAbsent(info.activityInfo.packageName, info)
            }
        }
        entries.remove(context.packageName)

        iconDir.mkdirs()
        val wanted = HashSet<String>()
        val apps = entries.map { (packageName, info) ->
            val icon = runCatching { cacheArtwork(pm, packageName, info) }.getOrNull()
            icon?.let { wanted.add(it.file.name) }
            InstalledApp(
                packageName = packageName,
                label = info.loadLabel(pm).toString(),
                iconPath = icon?.file?.absolutePath,
                isBanner = icon?.isBanner ?: false,
            )
        }
        iconDir.listFiles()?.filter { it.name !in wanted }?.forEach { it.delete() }
        return apps
    }

    private class Artwork(val file: File, val isBanner: Boolean)

    /** Renders the app's banner (or icon) to a PNG, reused until the package is updated. */
    private fun cacheArtwork(pm: PackageManager, packageName: String, info: ResolveInfo): Artwork? {
        val updated = pm.getPackageInfo(packageName, 0).lastUpdateTime
        val bannerFile = File(iconDir, "$packageName-$updated-banner.png")
        val iconFile = File(iconDir, "$packageName-$updated-icon.png")
        if (bannerFile.exists()) return Artwork(bannerFile, true)
        if (iconFile.exists()) return Artwork(iconFile, false)

        val activity = info.activityInfo
        val banner = activity.loadBanner(pm) ?: activity.applicationInfo.loadBanner(pm)
        if (banner != null) {
            writePng(banner, BANNER_WIDTH, BANNER_HEIGHT, bannerFile)
            return Artwork(bannerFile, true)
        }
        val icon = info.loadIcon(pm) ?: return null
        writePng(icon, ICON_SIZE, ICON_SIZE, iconFile)
        return Artwork(iconFile, false)
    }

    private companion object {
        const val BANNER_WIDTH = 640
        const val BANNER_HEIGHT = 360
        const val ICON_SIZE = 256
        const val HOME_BUTTON_CHECK_DELAY_MS = 300L
    }
}

internal fun writePng(drawable: Drawable, width: Int, height: Int, target: File) {
    val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
    drawable.setBounds(0, 0, width, height)
    drawable.draw(Canvas(bitmap))
    // Write to a temp file first so a half-written PNG is never picked up.
    val tmp = File(target.parentFile, target.name + ".tmp")
    tmp.outputStream().use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }
    bitmap.recycle()
    tmp.renameTo(target)
}
