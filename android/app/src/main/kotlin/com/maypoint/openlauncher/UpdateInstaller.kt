package com.maypoint.openlauncher

import android.content.Context
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.os.Build
import java.io.File

/**
 * Installs a downloaded update of this app through the TV's own ADB service:
 * silently, with no permission of its own, and from a shell that can open
 * the launcher again once the install has replaced this process.
 */
class UpdateInstaller(private val context: Context) {
    /** Only returns if the update was not installed, with why. */
    fun run(path: String): SetupResult {
        val apk = File(path)
        refusal(apk)?.let { return SetupResult(SetupOutcome.FAILED, it) }
        val activity = "${context.packageName}/${MainActivity::class.java.name}"
        return try {
            LocalAdb.use(context, LocalAdb.QUICK_TIMEOUT_MS) { adb ->
                adb.push(apk, REMOTE_APK, FILE_MODE, System.currentTimeMillis())
                adb.shell("rm -f $REMOTE_LOG")
                // Detached, so that it outlives this process and the connection.
                adb.shell(
                    "nohup sh -c 'pm install -r $REMOTE_APK > $REMOTE_LOG 2>&1 " +
                        "&& am start -n $activity; rm -f $REMOTE_APK' " +
                        "> /dev/null 2>&1 < /dev/null &",
                )
                // Still running: wait for the TV to say why it did not install.
                repeat(WAIT_SECONDS) {
                    Thread.sleep(1_000)
                    val said = adb.shell("cat $REMOTE_LOG 2> /dev/null").output.trim()
                    if (said.isNotEmpty() && !said.startsWith("Success")) {
                        return@use SetupResult(SetupOutcome.FAILED, said)
                    }
                }
                SetupResult(SetupOutcome.FAILED, "The TV did not finish installing it.")
            }
        } catch (e: Exception) {
            LocalAdb.failure(e)
        }
    }

    /**
     * Why [apk] is not an update of this app, or null. The shell could
     * install any app, so nothing but a newer copy of this one is handed
     * over; the TV itself then refuses one signed with another key.
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

    private companion object {
        const val REMOTE_APK = "/data/local/tmp/openlauncher-update.apk"
        const val REMOTE_LOG = "/data/local/tmp/openlauncher-update.log"
        const val FILE_MODE = 420 // 0644
        const val WAIT_SECONDS = 90

        @Suppress("DEPRECATION")
        val SIGNERS = if (Build.VERSION.SDK_INT >= 28) {
            PackageManager.GET_SIGNING_CERTIFICATES
        } else {
            PackageManager.GET_SIGNATURES
        }
    }
}
