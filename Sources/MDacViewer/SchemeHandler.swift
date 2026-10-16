import WebKit

/// Serves the bundled web assets (Web/ directory) to WKWebView over a custom
/// `app://` URL scheme. This avoids file:// restrictions and lets the editor
/// load its modules and resources reliably.
final class SchemeHandler: NSObject, WKURLSchemeHandler {
    private let baseURL: URL

    override init() {
        let resources = Bundle.main.resourceURL ?? Bundle.main.bundleURL
        baseURL = resources.appendingPathComponent("web", isDirectory: true).standardizedFileURL
        super.init()
    }

    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        guard let url = task.request.url else {
            task.didFailWithError(Self.error("Invalid request URL"))
            return
        }

        var relativePath = url.path
        if relativePath.isEmpty || relativePath == "/" {
            relativePath = "/index.html"
        }
        let fileURL = baseURL.appendingPathComponent(relativePath).standardizedFileURL

        // Path traversal guard + read.
        guard fileURL.path.hasPrefix(baseURL.path),
              let data = try? Data(contentsOf: fileURL) else {
            let response = HTTPURLResponse(url: url, statusCode: 404,
                                           httpVersion: "HTTP/1.1",
                                           headerFields: ["Content-Type": "text/plain"])!
            task.didReceive(response)
            task.didReceive(Data("Not found".utf8))
            task.didFinish()
            return
        }

        let headers = [
            "Content-Type": Self.mimeType(for: fileURL.pathExtension),
            "Content-Length": "\(data.count)",
            "Cache-Control": "no-cache",
            "Access-Control-Allow-Origin": "*",
        ]
        let response = HTTPURLResponse(url: url, statusCode: 200,
                                       httpVersion: "HTTP/1.1",
                                       headerFields: headers)!
        task.didReceive(response)
        task.didReceive(data)
        task.didFinish()
    }

    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {}

    private static func mimeType(for extensionName: String) -> String {
        switch extensionName.lowercased() {
        case "html": return "text/html"
        case "js", "mjs": return "text/javascript"
        case "css": return "text/css"
        case "md", "markdown", "txt": return "text/plain"
        case "json", "map": return "application/json"
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif": return "image/gif"
        case "svg": return "image/svg+xml"
        case "webp": return "image/webp"
        case "woff": return "font/woff"
        case "woff2": return "font/woff2"
        case "ttf": return "font/ttf"
        default: return "application/octet-stream"
        }
    }

    private static func error(_ message: String) -> NSError {
        NSError(domain: "MDacViewer.SchemeHandler", code: -1,
                userInfo: [NSLocalizedDescriptionKey: message])
    }
}
