package com.maypoint.openlauncher

import android.appwidget.AppWidgetHost
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.view.View
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

/**
 * Hosts widgets from installed apps. Each layout item that shows one gets its
 * own Android widget id, remembered here so the layout itself stays free of
 * device-specific numbers.
 *
 * [ask] shows one of the TV's own questions and tells whether the user agreed.
 */
class WidgetHost(
    private val context: Context,
    private val ask: suspend (Intent) -> Boolean,
) {
    private val supported =
        context.packageManager.hasSystemFeature(PackageManager.FEATURE_APP_WIDGETS)
    private val manager: AppWidgetManager? =
        if (supported) AppWidgetManager.getInstance(context) else null
    private val host = AppWidgetHost(context, HOST_ID)

    /** Layout item id -> "<widget id> <provider>". */
    private val bound = context.getSharedPreferences("widgets", Context.MODE_PRIVATE)

    // One at a time: binding may wait for the user's answer.
    private val binding = Mutex()

    fun providers(): List<WidgetProvider> {
        val manager = manager ?: return emptyList()
        val pm = context.packageManager
        return runCatching {
            manager.installedProviders.map { info ->
                WidgetProvider(
                    id = info.provider.flattenToShortString(),
                    label = info.loadLabel(pm),
                    appLabel = runCatching {
                        pm.getApplicationLabel(
                            pm.getApplicationInfo(info.provider.packageName, 0),
                        ).toString()
                    }.getOrDefault(info.provider.packageName),
                )
            }
        }.getOrDefault(emptyList())
    }

    /**
     * The widget id for [itemId], binding one to [provider] if it has none or
     * shows a different widget. Null if the TV or the user will not allow it.
     */
    suspend fun bind(itemId: String, provider: String): Int? = binding.withLock {
        val manager = manager ?: return null
        val component = ComponentName.unflattenFromString(provider) ?: return null
        bound.getString(itemId, null)?.split(' ', limit = 2)?.let { (id, boundTo) ->
            if (boundTo == provider && manager.getAppWidgetInfo(id.toInt()) != null) {
                return id.toInt()
            }
            host.deleteAppWidgetId(id.toInt())
        }
        val id = host.allocateAppWidgetId()
        val allowed = runCatching {
            manager.bindAppWidgetIdIfAllowed(id, component) || askToBind(id, component)
        }.getOrDefault(false)
        if (!allowed) {
            host.deleteAppWidgetId(id)
            bound.edit().remove(itemId).apply()
            return null
        }
        bound.edit().putString(itemId, "$id $provider").apply()
        id
    }

    /** The TV's "let this app show widgets?" question, which binds on a yes. */
    private suspend fun askToBind(id: Int, component: ComponentName): Boolean {
        val question = Intent(AppWidgetManager.ACTION_APPWIDGET_BIND)
            .putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, id)
            .putExtra(AppWidgetManager.EXTRA_APPWIDGET_PROVIDER, component)
        // Many TVs have no such screen.
        if (question.resolveActivity(context.packageManager) == null) return false
        return ask(question)
    }

    fun prune(itemIds: Collection<String>) {
        val editor = bound.edit()
        for ((itemId, value) in bound.all) {
            if (itemId in itemIds) continue
            (value as? String)?.substringBefore(' ')?.toIntOrNull()
                ?.let(host::deleteAppWidgetId)
            editor.remove(itemId)
        }
        editor.apply()
    }

    /** Widgets only update while the host is listening; do so while on screen. */
    fun start() {
        if (supported) runCatching { host.startListening() }
    }

    fun stop() {
        if (supported) runCatching { host.stopListening() }
    }

    val viewFactory = object : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
        override fun create(viewContext: Context, viewId: Int, args: Any?): PlatformView {
            val widgetId = (args as Number).toInt()
            val view: View =
                host.createView(viewContext, widgetId, manager?.getAppWidgetInfo(widgetId))
            return object : PlatformView {
                override fun getView() = view
                override fun dispose() {}
            }
        }
    }

    companion object {
        const val VIEW_TYPE = "openlauncher/appwidget"
        private const val HOST_ID = 1
    }
}
