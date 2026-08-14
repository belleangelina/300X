package com.yamibox300

import android.content.Intent
import android.content.ClipData
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.view.View
import android.view.WindowInsets
import android.view.WindowInsetsController
import android.webkit.CookieManager
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone

class MainActivity : FlutterActivity()
{
    companion object
    {
        private const val FORUM_FILE_SELECTOR_REQUEST_CODE = 43001
        private const val FORUM_COOKIE_HOST = "bbs.yamibo.com"
        private val FORUM_MIME_TYPE_PATTERN = Regex(
            "^(\\*/\\*|[a-z0-9][a-z0-9!#&^_.+\\-]*/" +
                "(\\*|[a-z0-9][a-z0-9!#&^_.+\\-]*))$",
        )
    }

    private var pendingForumFileSelectorResult: MethodChannel.Result? = null
    private var pendingForumFileSelectorAllowsMultiple = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine)
    {
        super.configureFlutterEngine(flutterEngine)
        installForumCookieChannel(flutterEngine)
        installForumDownloadedFileChannel(flutterEngine)
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
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.yamibox300/forum_file_selector",
        ).setMethodCallHandler(
            MethodChannel.MethodCallHandler
            {
                call, result ->
                if (call.method != "chooseFiles")
                {
                    result.notImplemented()
                    return@MethodCallHandler
                }
                openForumFileSelector(call.arguments, result)
            },
        )
    }

    private fun installForumCookieChannel(flutterEngine: FlutterEngine)
    {
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.yamibox300/forum_web_cookies",
        ).setMethodCallHandler(
            MethodChannel.MethodCallHandler
            {
                call, result ->
                when (call.method)
                {
                    "getCookies" -> getForumCookies(call.arguments, result)
                    "setCookie" -> setForumCookie(call.arguments, result)
                    "clearCookies" -> clearForumCookies(call.arguments, result)
                    else -> result.notImplemented()
                }
            },
        )
    }

    private fun installForumDownloadedFileChannel(flutterEngine: FlutterEngine)
    {
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.yamibox300/forum_downloaded_file",
        ).setMethodCallHandler(
            MethodChannel.MethodCallHandler
            {
                call, result ->
                if (call.method != "open")
                {
                    result.notImplemented()
                    return@MethodCallHandler
                }
                openForumDownloadedFile(call.arguments, result)
            },
        )
    }

    private fun getForumCookies(arguments: Any?, result: MethodChannel.Result)
    {
        val url = forumCookieUrl(arguments)
        if (url == null)
        {
            result.error("invalid_origin", "仅允许论坛 HTTPS Cookie", null)
            return
        }
        val header = CookieManager.getInstance().getCookie(url.toString())
        if (header.isNullOrBlank())
        {
            result.success(emptyList<Map<String, Any?>>())
            return
        }
        val cookies = mutableListOf<Map<String, Any?>>()
        for (part in header.split(';'))
        {
            val pair = part.trim()
            val separator = pair.indexOf('=')
            if (separator <= 0)
            {
                result.error("invalid_cookie", "Android Cookie 快照无法解析", null)
                return
            }
            cookies += mapOf(
                "name" to pair.substring(0, separator),
                "value" to pair.substring(separator + 1),
                "domain" to FORUM_COOKIE_HOST,
                "path" to "/",
                "secure" to false,
                "httpOnly" to false,
                "expiresEpochMilliseconds" to null,
                "maxAge" to null,
                "sameSite" to null,
                "attributesComplete" to false,
            )
        }
        result.success(cookies)
    }

    private fun setForumCookie(arguments: Any?, result: MethodChannel.Result)
    {
        val url = forumCookieUrl(arguments)
        val args = arguments as? Map<*, *>
        val cookie = args?.get("cookie") as? Map<*, *>
        if (url == null || cookie == null)
        {
            result.error("invalid_argument", "Cookie 参数无效", null)
            return
        }
        val header = buildForumCookieHeader(cookie)
        if (header == null)
        {
            result.error("invalid_cookie", "Cookie 属性无效", null)
            return
        }
        CookieManager.getInstance().setCookie(url.toString(), header)
        {
            accepted ->
            if (!accepted)
            {
                result.error("cookie_rejected", "Android 拒绝写入 Cookie", null)
                return@setCookie
            }
            CookieManager.getInstance().flush()
            result.success(null)
        }
    }

    private fun clearForumCookies(arguments: Any?, result: MethodChannel.Result)
    {
        if (forumCookieUrl(arguments) == null)
        {
            result.error("invalid_origin", "仅允许论坛 HTTPS Cookie", null)
            return
        }
        CookieManager.getInstance().removeAllCookies { _: Boolean ->
            CookieManager.getInstance().flush()
            result.success(null)
        }
    }

    private fun forumCookieUrl(arguments: Any?): Uri?
    {
        val args = arguments as? Map<*, *> ?: return null
        val value = args["url"] as? String ?: return null
        val uri = Uri.parse(value)
        if (uri.scheme != "https" ||
            uri.host != FORUM_COOKIE_HOST ||
            (uri.port != -1 && uri.port != 443) ||
            uri.encodedUserInfo != null ||
            uri.toString() != value)
        {
            return null
        }
        return uri
    }

    private fun buildForumCookieHeader(cookie: Map<*, *>): String?
    {
        val name = cookie["name"] as? String ?: return null
        val value = cookie["value"] as? String ?: return null
        val domain = cookie["domain"] as? String?
        val path = cookie["path"] as? String ?: return null
        val secure = cookie["secure"] as? Boolean ?: return null
        val httpOnly = cookie["httpOnly"] as? Boolean ?: return null
        val expires = cookie["expiresEpochMilliseconds"] as? Number
        val maxAge = cookie["maxAge"] as? Number
        val sameSite = cookie["sameSite"] as? String?
        if (!isValidCookieName(name) ||
            !isValidCookieValue(value) ||
            !isValidCookiePath(path) ||
            !isValidCookieDomain(domain) ||
            sameSite !in setOf(null, "Lax", "Strict", "None") ||
            (sameSite == "None" && !secure))
        {
            return null
        }
        val header = StringBuilder("$name=$value")
        if (expires != null)
        {
            val formatter = SimpleDateFormat(
                "EEE, dd MMM yyyy HH:mm:ss 'GMT'",
                Locale.US,
            )
            formatter.timeZone = TimeZone.getTimeZone("GMT")
            header.append("; Expires=")
            header.append(formatter.format(Date(expires.toLong())))
        }
        if (maxAge != null)
        {
            header.append("; Max-Age=").append(maxAge.toLong())
        }
        if (domain != null)
        {
            header.append("; Domain=").append(domain)
        }
        header.append("; Path=").append(path)
        if (secure)
        {
            header.append("; Secure")
        }
        if (httpOnly)
        {
            header.append("; HttpOnly")
        }
        if (sameSite != null)
        {
            header.append("; SameSite=").append(sameSite)
        }
        return header.toString()
    }

    private fun isValidCookieName(value: String): Boolean
    {
        val separators = "()<>@,;:\\\"/[]?={}"
        return value.isNotEmpty() && value.all {
            character -> character.code in 0x21..0x7e && character !in separators
        }
    }

    private fun isValidCookieValue(value: String): Boolean
    {
        return value.all {
            character -> character.code in 0x21..0x7e &&
                character !in "\";,\\"
        }
    }

    private fun isValidCookiePath(value: String): Boolean
    {
        return value.startsWith('/') && value.all {
            character -> character.code >= 0x20 && character != ';'
        }
    }

    private fun isValidCookieDomain(value: String?): Boolean
    {
        if (value == null)
        {
            return true
        }
        if (value != value.trim())
        {
            return false
        }
        val normalized = value.lowercase().removePrefix(".")
        return normalized == FORUM_COOKIE_HOST || normalized == "yamibo.com"
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?)
    {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != FORUM_FILE_SELECTOR_REQUEST_CODE)
        {
            return
        }
        val result = pendingForumFileSelectorResult ?: return
        pendingForumFileSelectorResult = null
        val allowMultiple = pendingForumFileSelectorAllowsMultiple
        pendingForumFileSelectorAllowsMultiple = false
        if (resultCode != RESULT_OK || data == null)
        {
            result.success(emptyList<String>())
            return
        }
        val selectedUris = linkedSetOf<Uri>()
        val clipData = data.clipData
        if (allowMultiple)
        {
            data.data?.let(selectedUris::add)
            if (clipData != null)
            {
                for (index in 0 until clipData.itemCount)
                {
                    clipData.getItemAt(index).uri?.let(selectedUris::add)
                }
            }
        }
        else
        {
            val selectedUri = data.data ?: clipData
                ?.takeIf { value -> value.itemCount > 0 }
                ?.getItemAt(0)
                ?.uri
            selectedUri?.let(selectedUris::add)
        }
        val contentUris = selectedUris.filter { uri -> uri.scheme == "content" }
        for (uri in contentUris)
        {
            retainForumFileReadPermission(uri, data.flags)
        }
        result.success(contentUris.map(Uri::toString))
    }

    override fun onDestroy()
    {
        pendingForumFileSelectorResult?.error(
            "activity_destroyed",
            "文件选择页面已关闭",
            null,
        )
        pendingForumFileSelectorResult = null
        pendingForumFileSelectorAllowsMultiple = false
        super.onDestroy()
    }

    private fun openForumFileSelector(
        arguments: Any?,
        result: MethodChannel.Result,
    )
    {
        if (isFinishing || isDestroyed)
        {
            result.error("activity_unavailable", "当前页面正在关闭", null)
            return
        }
        if (pendingForumFileSelectorResult != null)
        {
            result.error("file_selector_busy", "已有文件选择请求", null)
            return
        }
        val values = arguments as? Map<*, *>
        val allowMultiple = when (values?.get("mode"))
        {
            "open" -> false
            "openMultiple" -> true
            else ->
            {
                result.error("unsupported_mode", "仅支持打开已有文件", null)
                return
            }
        }
        val mimeTypes = normalizeForumMimeTypes(values["mimeTypes"])
        if (mimeTypes == null)
        {
            result.error("invalid_mime_types", "文件类型无效", null)
            return
        }
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = if (mimeTypes.size == 1) mimeTypes.first() else "*/*"
            if (mimeTypes.size > 1)
            {
                putExtra(Intent.EXTRA_MIME_TYPES, mimeTypes.toTypedArray())
            }
            putExtra(Intent.EXTRA_ALLOW_MULTIPLE, allowMultiple)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
        }
        pendingForumFileSelectorResult = result
        pendingForumFileSelectorAllowsMultiple = allowMultiple
        try
        {
            startActivityForResult(intent, FORUM_FILE_SELECTOR_REQUEST_CODE)
        }
        catch (error: Exception)
        {
            pendingForumFileSelectorResult = null
            pendingForumFileSelectorAllowsMultiple = false
            result.error("file_selector_failed", error.message, null)
        }
    }

    private fun normalizeForumMimeTypes(value: Any?): List<String>?
    {
        val values = value as? List<*> ?: return null
        val mimeTypes = linkedSetOf<String>()
        for (item in values)
        {
            val mimeType = (item as? String)?.trim()?.lowercase() ?: return null
            if (!FORUM_MIME_TYPE_PATTERN.matches(mimeType))
            {
                return null
            }
            if (mimeType == "*/*")
            {
                return listOf("*/*")
            }
            mimeTypes.add(mimeType)
        }
        return if (mimeTypes.isEmpty()) listOf("*/*") else mimeTypes.toList()
    }

    private fun retainForumFileReadPermission(uri: Uri, returnedFlags: Int)
    {
        val hasReadGrant = returnedFlags and Intent.FLAG_GRANT_READ_URI_PERMISSION != 0
        val canPersist = returnedFlags and Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION != 0
        if (!hasReadGrant || !canPersist)
        {
            return
        }
        try
        {
            contentResolver.takePersistableUriPermission(
                uri,
                Intent.FLAG_GRANT_READ_URI_PERMISSION,
            )
        }
        catch (_: SecurityException)
        {
            // The temporary read-only grant from ACTION_OPEN_DOCUMENT remains valid.
        }
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

    private fun openForumDownloadedFile(
        arguments: Any?,
        result: MethodChannel.Result,
    )
    {
        val values = arguments as? Map<*, *>
        val filePath = values?.get("filePath") as? String
        val mimeType = (values?.get("mimeType") as? String)?.trim()?.lowercase()
        if (filePath.isNullOrEmpty() ||
            !File(filePath).isAbsolute ||
            mimeType == null ||
            !FORUM_MIME_TYPE_PATTERN.matches(mimeType) ||
            mimeType == "*/*")
        {
            result.error("invalid_argument", "附件参数无效", null)
            return
        }
        try
        {
            val attachmentRoot = File(cacheDir, "forum-attachments").canonicalFile
            val file = File(filePath).canonicalFile
            if (!file.isFile ||
                !file.path.startsWith(attachmentRoot.path + File.separator))
            {
                result.error("invalid_file", "附件文件不在应用缓存目录", null)
                return
            }
            val uri = FileProvider.getUriForFile(
                this,
                "$packageName.update_files",
                file,
            )
            val intent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, mimeType)
                clipData = ClipData.newRawUri("forum-attachment", uri)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            if (intent.resolveActivity(packageManager) == null)
            {
                result.error("viewer_missing", "没有可用的文件查看器", null)
                return
            }
            startActivity(intent)
            result.success(null)
        }
        catch (error: Exception)
        {
            result.error("open_failed", "无法打开附件", null)
        }
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
