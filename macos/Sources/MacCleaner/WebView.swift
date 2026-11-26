import AppKit
import Foundation
import SwiftUI
import WebKit

/// Menyajikan file antarmuka (hasil build ui/dist) lewat skema maccleaner://app/
final class UISchemeHandler: NSObject, WKURLSchemeHandler {
    let root: URL

    init(root: URL) {
        self.root = root.standardizedFileURL
    }

    static let mime: [String: String] = [
        "html": "text/html; charset=utf-8", "js": "text/javascript; charset=utf-8",
        "css": "text/css; charset=utf-8", "svg": "image/svg+xml", "png": "image/png",
        "woff2": "font/woff2", "json": "application/json", "ico": "image/x-icon",
    ]

    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        guard let url = task.request.url else { return }
        var rel = url.path
        if rel.isEmpty || rel == "/" { rel = "/index.html" }
        let file = root.appendingPathComponent(String(rel.dropFirst())).standardizedFileURL
        guard file.path.hasPrefix(root.path + "/"), let data = try? Data(contentsOf: file) else {
            task.didFailWithError(NSError(domain: NSURLErrorDomain, code: NSURLErrorFileDoesNotExist))
            return
        }
        let type = UISchemeHandler.mime[file.pathExtension.lowercased()] ?? "application/octet-stream"
        let headers = ["Content-Type": type, "Content-Length": "\(data.count)",
                       "Access-Control-Allow-Origin": "*", "Cache-Control": "no-store"]
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: headers)!
        task.didReceive(response)
        task.didReceive(data)
        task.didFinish()
    }

    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {}
}

/// Jembatan JavaScript → Swift: window.webkit.messageHandlers.mc.postMessage({method, path, body})
@MainActor
final class BridgeHandler: NSObject, WKScriptMessageHandlerWithReply {
    let api = ApiBridge()
    /// Semua panggilan data diproses berurutan agar hasil pindai tidak dibaca & diubah bersamaan.
    private let queue = DispatchQueue(label: "maccleaner.api", qos: .userInitiated)

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage,
                               replyHandler: @escaping @MainActor @Sendable (Any?, String?) -> Void) {
        let msg = message.body as? [String: Any] ?? [:]
        let method = msg["method"] as? String ?? "GET"
        let path = msg["path"] as? String ?? ""
        let body = msg["body"] as? [String: Any] ?? [:]
        let route = path.components(separatedBy: "?").first ?? path

        if ApiBridge.mainThreadRoutes.contains(route) {
            replyHandler(BridgeHandler.encode(api.handleOnMain(path: route, body: body)), nil)
            return
        }
        queue.async { [api] in
            let result: Any
            do {
                result = try api.handle(method: method, path: path, body: body)
            } catch let e as ApiBridge.Failure {
                result = ["__error": e.message]
            } catch {
                result = ["__error": error.localizedDescription]
            }
            let json = BridgeHandler.encode(result)
            Task { @MainActor in replyHandler(json, nil) }
        }
    }

    /// Kirim sebagai string JSON agar tipe data (angka besar, null) utuh.
    nonisolated static func encode(_ value: Any) -> String {
        guard JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value),
              let text = String(data: data, encoding: .utf8) else {
            return "{\"__error\":\"Respons tidak valid\"}"
        }
        return text
    }
}

/// Menyimpan WKWebView agar menu aplikasi bisa memanggil antarmuka.
final class WebViewStore: ObservableObject {
    static let shared = WebViewStore()
    weak var webView: WKWebView?

    /// Jalankan perintah antarmuka, mis. run("scan", "/Users/budi").
    func run(_ command: String, _ argument: String? = nil) {
        var arg = ""
        if let a = argument,
           let data = try? JSONSerialization.data(withJSONObject: [a]),
           let s = String(data: data, encoding: .utf8) {
            arg = String(s.dropFirst().dropLast())   // ["…"] → "…" (sudah di-escape)
        }
        webView?.evaluateJavaScript("window.__mc && window.__mc.\(command)(\(arg))")
    }
}

/// Lokasi hasil build antarmuka.
enum UIBundle {
    static func locate() -> URL? {
        var candidates: [URL] = []
        if let res = Bundle.main.resourceURL { candidates.append(res.appendingPathComponent("ui")) }
        if let env = ProcessInfo.processInfo.environment["MACCLEANER_UI_DIR"] {
            candidates.append(URL(fileURLWithPath: env))
        }
        // `swift run` dari folder macos/ atau akar repo.
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        candidates.append(cwd.appendingPathComponent("../ui/dist"))
        candidates.append(cwd.appendingPathComponent("ui/dist"))
        return candidates.first { FileManager.default.fileExists(atPath: $0.appendingPathComponent("index.html").path) }
    }
}

struct WebContainer: NSViewRepresentable {
    func makeCoordinator() -> BridgeHandler { BridgeHandler() }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let root = UIBundle.locate()
        if let root = root {
            config.setURLSchemeHandler(UISchemeHandler(root: root), forURLScheme: "maccleaner")
        }
        config.userContentController.addScriptMessageHandler(context.coordinator, contentWorld: .page, name: "mc")

        let web = WKWebView(frame: .zero, configuration: config)
        web.setValue(false, forKey: "drawsBackground")   // tanpa kilatan putih di mode gelap
        web.allowsMagnification = false
        if #available(macOS 13.3, *) {
            #if DEBUG
            web.isInspectable = true
            #endif
        }
        if root != nil {
            web.load(URLRequest(url: URL(string: "maccleaner://app/index.html")!))
        } else {
            web.loadHTMLString("""
                <body style="font:14px -apple-system;padding:40px;color:#888">
                <h2>Antarmuka belum dibuild</h2>
                <p>Jalankan <code>cd ui && npm install && npm run build</code>, atau set MACCLEANER_UI_DIR.</p>
                </body>
                """, baseURL: nil)
        }
        WebViewStore.shared.webView = web
        return web
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
