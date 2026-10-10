package com.maypoint.openlauncher

import android.content.ComponentName
import android.content.Context
import android.provider.Settings
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification

/**
 * Lets the launcher see notifications other apps post, and, because Android
 * ties the two together, what they are playing. Switched on by automatic
 * setup; does nothing until then.
 */
class NotificationService : NotificationListenerService() {
    override fun onListenerConnected() {
        onConnected?.invoke()
    }

    override fun onNotificationPosted(sbn: StatusBarNotification) {
        onPosted?.invoke(sbn)
    }

    companion object {
        /** Set by the bridge while the launcher's UI is running. */
        var onConnected: (() -> Unit)? = null
        var onPosted: ((StatusBarNotification) -> Unit)? = null

        fun component(context: Context) =
            ComponentName(context, NotificationService::class.java)

        fun isEnabled(context: Context): Boolean {
            val enabled = Settings.Secure.getString(
                context.contentResolver,
                "enabled_notification_listeners",
            ) ?: return false
            return enabled.split(':').any {
                ComponentName.unflattenFromString(it) == component(context)
            }
        }
    }
}
