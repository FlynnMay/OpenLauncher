package com.maypoint.openlauncher

import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.provider.Settings

/**
 * What the user allows the launcher in the TV's own settings: whether each
 * [Access] is held, and the screen it is changed on.
 */
class SystemAccess(private val context: Context) {
    fun has(access: Access): Boolean = when (access) {
        Access.HOME_BUTTON -> HomeButtonService.isEnabled(context)
        Access.NOTIFICATIONS -> NotificationService.isEnabled(context)
    }

    fun change(access: Access) {
        if (access == Access.HOME_BUTTON && HomeButtonService.canSwitch(context)) {
            HomeButtonService.setEnabled(context, !has(access))
            return
        }
        open(screens(access) + Intent(Settings.ACTION_SETTINGS))
    }

    fun openTvSettings() = open(listOf(Intent(Settings.ACTION_SETTINGS)))

    /** Most specific first. */
    private fun screens(access: Access): List<Intent> = when (access) {
        Access.HOME_BUTTON -> listOf(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS))
        Access.NOTIFICATIONS -> listOfNotNull(
            if (Build.VERSION.SDK_INT >= 30) {
                Intent(Settings.ACTION_NOTIFICATION_LISTENER_DETAIL_SETTINGS).putExtra(
                    Settings.EXTRA_NOTIFICATION_LISTENER_COMPONENT_NAME,
                    NotificationService.component(context).flattenToString(),
                )
            } else {
                null
            },
            Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS),
        )
    }

    /** Starts the first of [intents] the TV has a screen for. */
    private fun open(intents: List<Intent>) {
        val pm = context.packageManager
        for (intent in intents) {
            // Some TVs answer with a stub that shows nothing.
            val screen = pm.queryIntentActivities(intent, PackageManager.MATCH_DEFAULT_ONLY)
                .map { it.activityInfo }
                .firstOrNull { !it.packageName.endsWith(".frameworkpackagestubs") }
                ?: continue
            context.startActivity(
                intent.setClassName(screen.packageName, screen.name)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            )
            return
        }
        throw FlutterError("no-settings", "This TV has no settings screen for it")
    }
}
