package com.yamibox300

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.view.View
import android.view.WindowInsets
import android.view.WindowInsetsController
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

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
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.yamibox300/app_update",
        ).setMethodCallHandler(
            MethodChannel.MethodCallHandler
            {
                call, result ->
                when (call.method)
                {
                    "primaryAbi" -> result.success(Build.SUPPORTED_ABIS.firstOrNull())
                    "canInstallPackages" -> result.success(canInstallPackages())
                    "openInstallPermission" ->
                    {
                        openInstallPermission()
                        result.success(null)
                    }
                    "installApk" ->
                    {
                        val filePath = call.arguments as? String
                        if (filePath == null)
                        {
                            result.error("invalid_argument", "Expected APK path", null)
                        }
                        else
                        {
                            installApk(filePath, result)
                        }
                    }
                    else -> result.notImplemented()
                }
            },
        )
    }

    private fun canInstallPackages(): Boolean
    {
        return Build.VERSION.SDK_INT < Build.VERSION_CODES.O ||
            packageManager.canRequestPackageInstalls()
    }

    private fun openInstallPermission()
    {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O)
        {
            return
        }
        startActivity(
            Intent(
                Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                Uri.parse("package:$packageName"),
            ),
        )
    }

    private fun installApk(filePath: String, result: MethodChannel.Result)
    {
        val file = File(filePath)
        if (!file.isFile || file.extension.lowercase() != "apk")
        {
            result.error("invalid_apk", "安装包不存在", null)
            return
        }
        val cacheRoot = cacheDir.canonicalFile
        val canonicalFile = file.canonicalFile
        if (!canonicalFile.path.startsWith(cacheRoot.path + File.separator))
        {
            result.error("invalid_apk", "安装包不在应用缓存目录", null)
            return
        }
        try
        {
            val uri = FileProvider.getUriForFile(
                this,
                "$packageName.update_files",
                canonicalFile,
            )
            val intent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, "application/vnd.android.package-archive")
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            if (intent.resolveActivity(packageManager) == null)
            {
                result.error("installer_missing", "找不到系统安装器", null)
                return
            }
            startActivity(intent)
            result.success(null)
        }
        catch (error: Exception)
        {
            result.error("install_failed", error.message, null)
        }
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
