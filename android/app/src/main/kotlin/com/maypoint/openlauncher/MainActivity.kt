package com.maypoint.openlauncher

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private var bridge: LauncherBridge? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        bridge = LauncherBridge(applicationContext, messenger).also {
            LauncherHostApi.setUp(messenger, it)
        }
    }

    override fun onResume() {
        super.onResume()
        bridge?.checkHomeButton()
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        LauncherHostApi.setUp(flutterEngine.dartExecutor.binaryMessenger, null)
        bridge?.dispose()
        bridge = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
