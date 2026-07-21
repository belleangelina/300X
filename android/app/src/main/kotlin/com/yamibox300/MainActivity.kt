package com.yamibox300

import android.os.Build
import android.view.View
import android.view.WindowInsets
import android.view.WindowInsetsController
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity()
{
    override fun configureFlutterEngine(flutterEngine: FlutterEngine)
    {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.yamibox300/system_ui",
        ).setMethodCallHandler(
            MethodChannel.MethodCallHandler
            {
                call, result ->
                if (call.method != "setImmersive")
                {
                    result.notImplemented()
                    return@MethodCallHandler
                }
                val enabled = call.arguments as? Boolean
                if (enabled == null)
                {
                    result.error("invalid_argument", "Expected a boolean", null)
                    return@MethodCallHandler
                }
                applyImmersiveMode(enabled)
                result.success(null)
            },
        )
    }

    private fun applyImmersiveMode(enabled: Boolean)
    {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R)
        {
            val controller = window.insetsController
            if (controller != null)
            {
                if (enabled)
                {
                    controller.systemBarsBehavior =
                        WindowInsetsController.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
                    controller.hide(WindowInsets.Type.systemBars())
                }
                else
                {
                    controller.show(WindowInsets.Type.systemBars())
                }
            }
            return
        }

        @Suppress("DEPRECATION")
        window.decorView.systemUiVisibility = if (enabled)
        {
            View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY or
                View.SYSTEM_UI_FLAG_LAYOUT_STABLE or
                View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION or
                View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN or
                View.SYSTEM_UI_FLAG_HIDE_NAVIGATION or
                View.SYSTEM_UI_FLAG_FULLSCREEN
        }
        else
        {
            View.SYSTEM_UI_FLAG_LAYOUT_STABLE
        }
    }
}
