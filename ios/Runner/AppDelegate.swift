import Flutter
import UIKit
import WebKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate,
  UIDocumentInteractionControllerDelegate
{
  private var forumDocumentController: UIDocumentInteractionController?
  private var forumDocumentPreviewing = false

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let cookieChannel = FlutterMethodChannel(
      name: "com.yamibox300/forum_web_cookies",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    cookieChannel.setMethodCallHandler { [weak self] call, result in
      self?.handleForumCookieCall(call, result: result)
    }
    let attachmentChannel = FlutterMethodChannel(
      name: "com.yamibox300/forum_downloaded_file",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    attachmentChannel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "open" else {
        result(FlutterMethodNotImplemented)
        return
      }
      self?.openForumDownloadedFile(call.arguments, result: result)
    }
  }

  private func openForumDownloadedFile(
    _ arguments: Any?,
    result: @escaping FlutterResult
  ) {
    guard
      forumDocumentController == nil,
      let values = arguments as? [String: Any],
      let filePath = values["filePath"] as? String,
      let mimeType = values["mimeType"] as? String,
      filePath.first == "/",
      isValidForumMimeType(mimeType),
      let cacheRoot = FileManager.default.urls(
        for: .cachesDirectory,
        in: .userDomainMask
      ).first
    else {
      result(FlutterError(
        code: "invalid_argument",
        message: "附件参数无效",
        details: nil
      ))
      return
    }
    let attachmentRoot = cacheRoot
      .appendingPathComponent("forum-attachments", isDirectory: true)
      .standardizedFileURL
      .resolvingSymlinksInPath()
    let fileURL = URL(fileURLWithPath: filePath)
      .standardizedFileURL
      .resolvingSymlinksInPath()
    let rootPrefix = attachmentRoot.path.hasSuffix("/")
      ? attachmentRoot.path
      : attachmentRoot.path + "/"
    guard fileURL.path.hasPrefix(rootPrefix) else {
      result(FlutterError(
        code: "invalid_file",
        message: "附件文件不在应用缓存目录",
        details: nil
      ))
      return
    }
    do {
      let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
      guard values.isRegularFile == true else {
        throw CocoaError(.fileReadNoSuchFile)
      }
    } catch {
      result(FlutterError(
        code: "invalid_file",
        message: "附件文件不存在",
        details: nil
      ))
      return
    }
    guard let viewController = activeViewController() else {
      result(FlutterError(
        code: "viewer_unavailable",
        message: "当前页面无法打开附件",
        details: nil
      ))
      return
    }
    let controller = UIDocumentInteractionController(url: fileURL)
    controller.delegate = self
    forumDocumentController = controller
    forumDocumentPreviewing = false
    let sourceRect = CGRect(
      x: viewController.view.bounds.midX,
      y: viewController.view.bounds.midY,
      width: 1,
      height: 1
    )
    guard controller.presentOptionsMenu(
      from: sourceRect,
      in: viewController.view,
      animated: true
    ) else {
      forumDocumentController = nil
      result(FlutterError(
        code: "viewer_missing",
        message: "没有可用的文件查看器",
        details: nil
      ))
      return
    }
    result(nil)
  }

  private func isValidForumMimeType(_ value: String) -> Bool {
    let pattern = #"^[a-z0-9][a-z0-9!#&^_.+\-]*/[a-z0-9][a-z0-9!#&^_.+\-]*$"#
    return value.range(of: pattern, options: .regularExpression) != nil
  }

  private func activeViewController() -> UIViewController? {
    let windows = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .flatMap(\.windows)
    var current = windows.first(where: \.isKeyWindow)?.rootViewController
      ?? windows.first?.rootViewController
    while let presented = current?.presentedViewController {
      current = presented
    }
    if let navigation = current as? UINavigationController {
      return navigation.visibleViewController ?? navigation
    }
    if let tabs = current as? UITabBarController {
      return tabs.selectedViewController ?? tabs
    }
    return current
  }

  func documentInteractionControllerDidDismissOptionsMenu(
    _ controller: UIDocumentInteractionController
  ) {
    DispatchQueue.main.async { [weak self, weak controller] in
      guard
        let self,
        let controller,
        self.forumDocumentController === controller,
        !self.forumDocumentPreviewing
      else {
        return
      }
      self.forumDocumentController = nil
    }
  }

  func documentInteractionControllerWillBeginPreview(
    _ controller: UIDocumentInteractionController
  ) {
    if forumDocumentController === controller {
      forumDocumentPreviewing = true
    }
  }

  func documentInteractionControllerDidEndPreview(
    _ controller: UIDocumentInteractionController
  ) {
    if forumDocumentController === controller {
      forumDocumentPreviewing = false
      forumDocumentController = nil
    }
  }

  private func handleForumCookieCall(
    _ call: FlutterMethodCall,
    result: @escaping FlutterResult
  ) {
    switch call.method {
    case "getCookies":
      getForumCookies(arguments: call.arguments, result: result)
    case "setCookie":
      setForumCookie(arguments: call.arguments, result: result)
    case "clearCookies":
      clearForumCookies(arguments: call.arguments, result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func getForumCookies(arguments: Any?, result: @escaping FlutterResult) {
    guard let url = forumCookieURL(arguments) else {
      result(FlutterError(
        code: "invalid_origin",
        message: "仅允许论坛 HTTPS Cookie",
        details: nil
      ))
      return
    }
    WKWebsiteDataStore.default().httpCookieStore.getAllCookies { cookies in
      let values = cookies.compactMap { cookie -> [String: Any]? in
        guard self.cookie(cookie, matches: url) else {
          return nil
        }
        return [
          "name": cookie.name,
          "value": cookie.value,
          "domain": cookie.domain,
          "path": cookie.path,
          "secure": cookie.isSecure,
          "httpOnly": cookie.isHTTPOnly,
          "expiresEpochMilliseconds": cookie.expiresDate.map {
            Int64($0.timeIntervalSince1970 * 1000) as Any
          } ?? NSNull(),
          "maxAge": cookie.properties?[.maximumAge].flatMap {
            Int(String(describing: $0))
          }.map { $0 as Any } ?? NSNull(),
          "sameSite": cookie.properties?[.sameSitePolicy].map {
            String(describing: $0) as Any
          } ?? NSNull(),
          "attributesComplete": true,
        ]
      }
      result(values)
    }
  }

  private func setForumCookie(arguments: Any?, result: @escaping FlutterResult) {
    guard
      let url = forumCookieURL(arguments),
      let arguments = arguments as? [String: Any],
      let values = arguments["cookie"] as? [String: Any],
      let properties = forumCookieProperties(values, url: url),
      let cookie = HTTPCookie(properties: properties)
    else {
      result(FlutterError(
        code: "invalid_cookie",
        message: "Cookie 属性无效",
        details: nil
      ))
      return
    }
    WKWebsiteDataStore.default().httpCookieStore.setCookie(cookie) {
      result(nil)
    }
  }

  private func clearForumCookies(
    arguments: Any?,
    result: @escaping FlutterResult
  ) {
    guard let url = forumCookieURL(arguments) else {
      result(FlutterError(
        code: "invalid_origin",
        message: "仅允许论坛 HTTPS Cookie",
        details: nil
      ))
      return
    }
    let store = WKWebsiteDataStore.default().httpCookieStore
    store.getAllCookies { cookies in
      let group = DispatchGroup()
      for cookie in cookies where self.cookie(cookie, matches: url) {
        group.enter()
        store.delete(cookie) {
          group.leave()
        }
      }
      group.notify(queue: .main) {
        result(nil)
      }
    }
  }

  private func forumCookieURL(_ arguments: Any?) -> URL? {
    guard
      let arguments = arguments as? [String: Any],
      let value = arguments["url"] as? String,
      let components = URLComponents(string: value),
      components.scheme == "https",
      components.host == Self.forumCookieHost,
      components.port == nil || components.port == 443,
      components.user == nil,
      components.password == nil,
      components.string == value
    else {
      return nil
    }
    return components.url
  }

  private func forumCookieProperties(
    _ values: [String: Any],
    url: URL
  ) -> [HTTPCookiePropertyKey: Any]? {
    guard
      let name = values["name"] as? String,
      let value = values["value"] as? String,
      let path = values["path"] as? String,
      let secure = values["secure"] as? Bool,
      let httpOnly = values["httpOnly"] as? Bool,
      isValidCookieName(name),
      isValidCookieValue(value),
      path.first == "/",
      !path.contains(";"),
      let host = url.host
    else {
      return nil
    }
    let domain = values["domain"] as? String ?? host
    guard domain == domain.trimmingCharacters(in: .whitespacesAndNewlines) else {
      return nil
    }
    let normalizedDomain = String(
      domain.lowercased().drop(while: { $0 == "." })
    )
    guard normalizedDomain == host || normalizedDomain == "yamibo.com" else {
      return nil
    }
    var properties: [HTTPCookiePropertyKey: Any] = [
      .name: name,
      .value: value,
      .domain: domain,
      .path: path,
    ]
    if secure {
      properties[.secure] = "TRUE"
    }
    if httpOnly {
      properties[HTTPCookiePropertyKey(rawValue: "HttpOnly")] = "TRUE"
    }
    if let expires = values["expiresEpochMilliseconds"] as? NSNumber {
      properties[.expires] = Date(
        timeIntervalSince1970: expires.doubleValue / 1000
      )
    }
    if let maxAge = values["maxAge"] as? NSNumber {
      properties[.maximumAge] = String(maxAge.int64Value)
    }
    if let sameSite = values["sameSite"] as? String {
      guard ["Lax", "Strict", "None"].contains(sameSite),
            sameSite != "None" || secure else {
        return nil
      }
      properties[.sameSitePolicy] = sameSite
    }
    return properties
  }

  private func cookie(_ cookie: HTTPCookie, matches url: URL) -> Bool {
    guard let host = url.host?.lowercased() else {
      return false
    }
    let domain = String(
      cookie.domain.lowercased().drop(while: { $0 == "." })
    )
    return domain == host || domain == "yamibo.com"
  }

  private func isValidCookieName(_ value: String) -> Bool {
    let separators = CharacterSet(charactersIn: "()<>@,;:\\\"/[]?={}")
    return !value.isEmpty && value.unicodeScalars.allSatisfy {
      $0.value >= 0x21 && $0.value <= 0x7e && !separators.contains($0)
    }
  }

  private func isValidCookieValue(_ value: String) -> Bool {
    let forbidden = CharacterSet(charactersIn: "\";,\\")
    return value.unicodeScalars.allSatisfy {
      $0.value >= 0x21 && $0.value <= 0x7e && !forbidden.contains($0)
    }
  }

  private static let forumCookieHost = "bbs.yamibo.com"
}
