package com.maypoint.openlauncher

import android.content.Context
import kotlinx.coroutines.delay

/**
 * One-press setup. Some of what the launcher needs can only be granted from
 * an ADB shell, so this connects to the TV's own ADB service, the way a
 * computer would, and runs the commands itself. The TV asks the user to allow
 * the connection the first time.
 */
class DeviceSetup(private val context: Context) {
    suspend fun run(): SetupResult {
        val pkg = context.packageName
        try {
            val refusal = LocalAdb.use(context, LocalAdb.PROMPT_TIMEOUT_MS) { adb ->
                val grant = adb.shell("pm grant $pkg android.permission.WRITE_SECURE_SETTINGS")
                if (grant.exitCode != 0) return@use grant.allOutput.trim()
                // TCL TVs refuse to start a third-party service without these;
                // other TVs do not know the names and reject them, harmlessly.
                // The uid-level mode is the one that matters: TCL resets the
                // package-level mode to "ignore" on every boot.
                for (op in listOf("AUTO_START", "ASSOC_START")) {
                    adb.shell("appops set --uid $pkg $op allow")
                    adb.shell("appops set $pkg $op allow")
                }
                // Optional extras; a TV that lacks one just says so.
                // Seeing notifications and what is playing:
                adb.shell(
                    "cmd notification allow_listener " +
                        NotificationService.component(context).flattenToString(),
                )
                // Showing other apps' widgets:
                adb.shell(WidgetHost.grantCommand(context))
                null
            }
            if (refusal != null) return SetupResult(SetupOutcome.FAILED, refusal)
        } catch (e: Exception) {
            return LocalAdb.failure(e)
        }
        // Off then on, with a pause the system can observe: a service that was
        // already on but had been refused is only retried when the setting changes.
        HomeButtonService.setEnabled(context, false)
        delay(SETTING_SETTLE_MS)
        HomeButtonService.setEnabled(context, true)
        return SetupResult(SetupOutcome.DONE)
    }

    private companion object {
        const val SETTING_SETTLE_MS = 1_000L
    }
}
