import UIKit
import WebKit

// AN Quotation — iPhone app (thin client).
// No data lives on the phone. The screens and all data come from the Quotation Sync server on the Synology NAS (/app/).
// This shell adds: server discovery, PDF making (A4, with footer) + share sheet, WhatsApp / links, file saving (Excel), offline screen.

let kServers = "qt_servers"
let kApiKey = "qt_api_key"
let defaultServers = [
    "https://quotation.audionation.synology.me",
    "http://quotation.audionation.synology.me:8858",
    "http://192.168.1.20:8858",
]
let defaultKey = "qs-542204bd4f67a3b43f0406ec"

enum Store {
    static var d: UserDefaults { .standard }
    static var servers: [String] {
        get { (d.stringArray(forKey: kServers) ?? defaultServers).filter { !$0.isEmpty } }
        set { d.set(newValue, forKey: kServers) }
    }
    static var apiKey: String {
        get { d.string(forKey: kApiKey) ?? defaultKey }
        set { d.set(newValue, forKey: kApiKey) }
    }
}

enum Server {
    static func find(_ done: @escaping (String?) -> Void) {
        let list = Store.servers
        func tryAt(_ i: Int) {
            guard i < list.count, let url = URL(string: list[i] + "/health") else { done(nil); return }
            var req = URLRequest(url: url, timeoutInterval: 6)
            req.cachePolicy = .reloadIgnoringLocalCacheData
            URLSession.shared.dataTask(with: req) { data, resp, _ in
                if (resp as? HTTPURLResponse)?.statusCode == 200, let d = data,
                   let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any], j["ok"] != nil {
                    done(list[i])
                } else { tryAt(i + 1) }
            }.resume()
        }
        tryAt(0)
    }
}

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    let main = QuoteViewController()

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = main
        window.backgroundColor = UIColor(red: 0.07, green: 0.07, blue: 0.09, alpha: 1)
        window.makeKeyAndVisible()
        self.window = window
        return true
    }

    func applicationDidBecomeActive(_ application: UIApplication) { main.resumed() }
}

final class QuoteViewController: UIViewController, WKScriptMessageHandler, WKNavigationDelegate, WKUIDelegate {
    private var webView: WKWebView!
    private var base: String?
    private var pdfView: WKWebView?
    private var pdfJob: (footer: String, name: String, how: String)?
    private var lastActive = Date()

    override func loadView() {
        let config = WKWebViewConfiguration()
        config.userContentController.add(self, name: "native")
        let js = "window.QS_NATIVE = true; window.QS_KEY = '\(Store.apiKey)';"
        config.userContentController.addUserScript(WKUserScript(source: js, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        config.websiteDataStore = .default()
        webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.isOpaque = false
        webView.backgroundColor = UIColor(red: 0.07, green: 0.07, blue: 0.09, alpha: 1)
        webView.scrollView.backgroundColor = webView.backgroundColor
        webView.scrollView.bounces = false
        webView.allowsLinkPreview = false
        view = webView
    }

    override func viewDidLoad() { super.viewDidLoad(); connect() }
    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }

    func resumed() {
        if base == nil { connect() } else if Date().timeIntervalSince(lastActive) > 600 {
            webView.evaluateJavaScript("window.QS&&QS.kick&&QS.kick(200)") { _, _ in }
        }
        lastActive = Date()
    }

    func connect() {
        showOffline(message: "NAS se jud raha hoon…")
        Server.find { [weak self] found in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if let b = found, let url = URL(string: b + "/app/?key=" + Store.apiKey) {
                    self.base = b
                    self.webView.load(URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 25))
                } else {
                    self.base = nil
                    self.showOffline(message: "NAS se connect nahi ho paya. Wi-Fi / VPN check kijiye, ya neeche address theek kijiye.")
                }
            }
        }
    }

    private func showOffline(message: String) {
        guard let url = Bundle.main.url(forResource: "offline", withExtension: "html", subdirectory: "web") else { return }
        webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        let servers = (try? String(data: JSONSerialization.data(withJSONObject: Store.servers), encoding: .utf8)) ?? "[]"
        let msg = message.replacingOccurrences(of: "'", with: "\\'")
        let js = "window.__init && window.__init(\(servers), '\(Store.apiKey)', '\(msg)')"
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { self.webView.evaluateJavaScript(js) { _, _ in } }
    }

    // MARK: messages from the page
    func userContentController(_ c: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "native", let body = message.body as? [String: Any], let type = body["t"] as? String else { return }
        switch type {
        case "haptic":
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        case "open":
            if let s = body["url"] as? String, let url = URL(string: s) { openExternal(url) }
        case "settings":
            if let k = body["key"] as? String, !k.isEmpty { Store.apiKey = k }
            if let s = body["servers"] as? [String] {
                let clean = s.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                    .map { $0.hasPrefix("http") ? $0 : "http://" + $0 }
                if !clean.isEmpty { Store.servers = clean }
            }
            if (body["reconnect"] as? Bool) == true { connect() }
        case "file":
            if let name = body["name"] as? String, let b64 = body["b64"] as? String, let data = Data(base64Encoded: b64) {
                let f = FileManager.default.temporaryDirectory.appendingPathComponent(name)
                try? data.write(to: f)
                share(f)
            }
        case "pdf":
            makePdf(html: body["html"] as? String ?? "", footer: body["footer"] as? String ?? "",
                    name: body["name"] as? String ?? "Quotation", how: body["how"] as? String ?? "share")
        default: break
        }
    }

    private func share(_ file: URL) {
        let vc = UIActivityViewController(activityItems: [file], applicationActivities: nil)
        vc.popoverPresentationController?.sourceView = view
        var top: UIViewController = self
        while let p = top.presentedViewController { top = p }
        top.present(vc, animated: true)
    }

    private func openExternal(_ url: URL) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        if url.host == "wa.me", let comps = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            let phone = url.path.replacingOccurrences(of: "/", with: "")
            let text = comps.queryItems?.first(where: { $0.name == "text" })?.value ?? ""
            var w = URLComponents(string: "whatsapp://send")!
            w.queryItems = [URLQueryItem(name: "phone", value: phone), URLQueryItem(name: "text", value: text)]
            if let wu = w.url, UIApplication.shared.canOpenURL(wu) { UIApplication.shared.open(wu); return }
        }
        UIApplication.shared.open(url)
    }

    // MARK: PDF (A4) — the page's HTML is rendered off-screen and printed to a PDF file, then shared
    private func makePdf(html: String, footer: String, name: String, how: String) {
        pdfJob = (footer, name, how)
        let w = WKWebView(frame: CGRect(x: 0, y: 0, width: 794, height: 1123))
        w.navigationDelegate = self
        w.isHidden = true
        view.insertSubview(w, at: 0)
        pdfView = w
        w.loadHTMLString(html, baseURL: URL(string: (base ?? "") + "/"))
    }

    private func finishPdf() {
        guard let w = pdfView, let job = pdfJob else { return }
        let r = FooterRenderer(footer: job.footer)
        r.addPrintFormatter(w.viewPrintFormatter(), startingAtPageAt: 0)
        let paper = CGRect(x: 0, y: 0, width: 595.2, height: 841.8)
        r.setValue(NSValue(cgRect: paper), forKey: "paperRect")
        r.setValue(NSValue(cgRect: paper.insetBy(dx: 0, dy: 0)), forKey: "printableRect")
        let data = NSMutableData()
        UIGraphicsBeginPDFContextToData(data, paper, nil)
        r.prepare(forDrawingPages: NSRange(location: 0, length: r.numberOfPages))
        let bounds = UIGraphicsGetPDFContextBounds()
        for i in 0..<r.numberOfPages {
            UIGraphicsBeginPDFPage()
            r.drawPage(at: i, in: bounds)
        }
        UIGraphicsEndPDFContext()
        let safe = job.name.replacingOccurrences(of: "/", with: "-")
        let f = FileManager.default.temporaryDirectory.appendingPathComponent(safe + ".pdf")
        try? (data as Data).write(to: f)
        w.removeFromSuperview(); pdfView = nil
        let how = job.how; pdfJob = nil
        if how != "none" { share(f) }
    }

    // MARK: navigation — stay on the NAS page; everything else opens outside
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if webView === pdfView {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { self.finishPdf() }   // let pictures arrive
        }
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if webView === pdfView { decisionHandler(.allow); return }
        guard let url = navigationAction.request.url else { decisionHandler(.cancel); return }
        let scheme = url.scheme?.lowercased() ?? ""
        if scheme == "file" || scheme == "about" || scheme == "blob" || scheme == "data" { decisionHandler(.allow); return }
        if let b = base, let bh = URL(string: b)?.host, url.host == bh, scheme == "http" || scheme == "https" { decisionHandler(.allow); return }
        if navigationAction.navigationType == .other && navigationAction.targetFrame?.isMainFrame == true && base == nil {
            decisionHandler(.allow); return
        }
        decisionHandler(.cancel)
        openExternal(url)
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url { openExternal(url) }
        return nil
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        if webView === pdfView { return }
        if base != nil { base = nil; showOffline(message: "NAS se connection toot gaya. Neeche 'Dobara jodiye' dabaiye.") }
    }

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        let a = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        a.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler() })
        present(a, animated: true)
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        let a = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        a.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in completionHandler(false) })
        a.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler(true) })
        present(a, animated: true)
    }

    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (String?) -> Void) {
        let a = UIAlertController(title: nil, message: prompt, preferredStyle: .alert)
        a.addTextField { $0.text = defaultText }
        a.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in completionHandler(nil) })
        a.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler(a.textFields?.first?.text) })
        present(a, animated: true)
    }
}

/// Draws the small footer line (page x / y) at the bottom of every PDF page.
final class FooterRenderer: UIPrintPageRenderer {
    let footer: String
    init(footer: String) { self.footer = footer; super.init() }
    override func drawFooterForPage(at pageIndex: Int, in footerRect: CGRect) {
        let text = (footer.isEmpty ? "" : footer + "   ") + "\(pageIndex + 1) / \(numberOfPages)"
        let attrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 7.5), .foregroundColor: UIColor.gray]
        let s = NSAttributedString(string: text, attributes: attrs)
        let sz = s.size()
        s.draw(at: CGPoint(x: footerRect.midX - sz.width / 2, y: footerRect.midY - sz.height / 2))
    }
}
