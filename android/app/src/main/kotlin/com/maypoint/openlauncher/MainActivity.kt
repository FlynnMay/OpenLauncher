package com.maypoint.openlauncher

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private var bridge: LauncherBridge? = null
    private var widgets: WidgetHost? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        val widgets = WidgetHost(applicationContext).also { widgets = it }
        flutterEngine.platformViewsController.registry
            .registerViewFactory(WidgetHost.VIEW_TYPE, widgets.viewFactory)
        bridge = LauncherBridge(applicationContext, messenger, widgets).also {
            LauncherHostApi.setUp(messenger, it)
        }
    }

    override fun onStart() {
        super.onStart()
        widgets?.start()
    }

    override fun onStop() {
        widgets?.stop()
        super.onStop()
    }

    override fun onResume() {
        super.onResume()
        bridge?.checkHomeButton()
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        LauncherHostApi.setUp(flutterEngine.dartExecutor.binaryMessenger, null)
        bridge?.dispose()
        bridge = null
        widgets = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
