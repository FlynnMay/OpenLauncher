package com.maypoint.openlauncher

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

class MainActivity : FlutterActivity() {
    private var bridge: LauncherBridge? = null
    private var widgets: WidgetHost? = null
    private var answer: CompletableDeferred<Boolean>? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        val widgets = WidgetHost(applicationContext, ::ask).also { widgets = it }
        flutterEngine.platformViewsController.registry
            .registerViewFactory(WidgetHost.VIEW_TYPE, widgets.viewFactory)
        bridge = LauncherBridge(applicationContext, messenger, widgets).also {
            LauncherHostApi.setUp(messenger, it)
        }
    }

    /** Shows one of the TV's own questions; whether the user agreed. */
    private suspend fun ask(question: Intent): Boolean = withContext(Dispatchers.Main) {
        val waiting = CompletableDeferred<Boolean>().also { answer = it }
        startActivityForResult(question, ASK)
        waiting.await()
    }

    @Deprecated("FlutterActivity offers no other way to hear an answer")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        @Suppress("DEPRECATION")
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == ASK) answer?.complete(resultCode == RESULT_OK)
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
        UpdateInstaller.relaunched(this)
        bridge?.checkHomeButton()
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        LauncherHostApi.setUp(flutterEngine.dartExecutor.binaryMessenger, null)
        bridge?.dispose()
        bridge = null
        widgets = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    private companion object {
        const val ASK = 1
    }
}
