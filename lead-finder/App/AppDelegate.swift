import UIKit
import WebKit
import UserNotifications
import BackgroundTasks

// AN Lead Finder — iPhone app.
// The leads, filters and screens come from the Lead Finder scanner on the Synology NAS (port 8857).
// This native shell adds: one-tap call / WhatsApp, new-lead notifications (checked in the background),
// red badge with the number of new hot leads, Excel export through the iPhone share sheet,
// pull-to-refresh, and an offline screen to set the NAS address.

let kServers = "lf_servers"
let kApiKey = "lf_api_key"
let kLastSeen = "lf_last_seen"
let kMinScore = "lf_notify_min"
let defaultServers = [
    "https://lead-finder.audionation.synology.me",
    "http://lead-finder.audionation.synology.me",
    "http://192.168.1.20:8857",
]
let defaultKey = "lf-an-7c21e9f4b0d8a356"
let refreshTaskId = "com.audionation.leadfinder.refresh"

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
    static var lastSeen: Double {
        get { d.double(forKey: kLastSeen) }
        set { d.set(newValue, forKey: kLastSeen) }
    }
    static var minScore: Int {
        get { d.object(forKey: kMinScore) == nil ? 50 : d.integer(forKey: kMinScore) }
        set { d.set(newValue, forKey: kMinScore) }
    }
}

// MARK: - Scanner API (used by background checks)
enum Scanner {
    /// First server that answers /health
    static func findServer(_ done: @escaping (String?) -> Void) {
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

    /// Fetch leads newer than lastSeen, post notifications for hot ones, update badge.
    static func checkNewLeads(_ done: @escaping (Bool) -> Void) {
        findServer { base in
            guard let base = base else { done(false); return }
            let since = Store.lastSeen > 0 ? Store.lastSeen : Date().timeIntervalSince1970 - 86400
            guard let url = URL(string: "\(base)/leads?since=\(since)&limit=200") else { done(false); return }
            var req = URLRequest(url: url, timeoutInterval: 20)
            req.setValue(Store.apiKey, forHTTPHeaderField: "X-API-Key")
            URLSession.shared.dataTask(with: req) { data, _, _ in
                guard let d = data, let arr = try? JSONSerialization.jsonObject(with: d) as? [[String: Any]] else {
                    done(false); return
                }
                let hot = arr.filter { ($0["score"] as? Int ?? 0) >= Store.minScore }
                if let maxTs = arr.compactMap({ $0["created_at"] as? Double }).max() { Store.lastSeen = maxTs }
                Notify.post(hot)
                done(true)
            }.resume()
        }
    }
}

// MARK: - Local notifications
enum Notify {
    static let roles = ["owner": "Owner", "architect": "Architect", "builder": "Contractor/Builder", "dealer": "Dealer"]

    static func ask(_ done: ((Bool) -> Void)? = nil) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { ok, _ in
            DispatchQueue.main.async { done?(ok) }
        }
    }

    static func post(_ leads: [[String: Any]]) {
        guard !leads.isEmpty else { return }
        let c = UNUserNotificationCenter.current()
        for l in leads.prefix(5) {
            let n = UNMutableNotificationContent()
            let score = l["score"] as? Int ?? 0
            let city = ((l["city"] as? String) ?? "").components(separatedBy: "/").first ?? ""
            n.title = "🔥 Nayi lead · \(city) · Score \(score)"
            var body = "\(l["locality"] as? String ?? "") — \(l["title"] as? String ?? "")"
            let role = roles[l["contact_role"] as? String ?? ""] ?? ""
            let name = l["contact_name"] as? String ?? ""
            if !role.isEmpty || !name.isEmpty { body += "\n\(role) \(name)".trimmingCharacters(in: .whitespaces) }
            if let ph = l["phone"] as? String, !ph.isEmpty { body += " · 📞 \(ph)" }
            n.body = body
            n.sound = .default
            n.userInfo = ["lead": l["id"] as? String ?? ""]
            c.add(UNNotificationRequest(identifier: l["id"] as? String ?? UUID().uuidString, content: n, trigger: nil))
        }
        if leads.count > 5 {
            let n = UNMutableNotificationContent()
            n.title = "\(leads.count) nayi hot leads"
            n.body = "Lead Finder kholkar dekhiye"
            n.sound = .default
            c.add(UNNotificationRequest(identifier: "batch-\(Date().timeIntervalSince1970)", content: n, trigger: nil))
        }
        DispatchQueue.main.async {
            UIApplication.shared.applicationIconBadgeNumber += leads.count
        }
    }
}

// MARK: - App
@main
final class AppDelegate: UIResponder, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    var window: UIWindow?
    let main = LeadViewController()

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        BGTaskScheduler.shared.register(forTaskWithIdentifier: refreshTaskId, using: nil) { task in
            self.handleRefresh(task as! BGAppRefreshTask)
        }
        // older-style background fetch as a second chance
        application.setMinimumBackgroundFetchInterval(30 * 60)

        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = main
        window.backgroundColor = UIColor(red: 0.059, green: 0.078, blue: 0.102, alpha: 1)
        window.makeKeyAndVisible()
        self.window = window
        Notify.ask()
        return true
    }

    func applicationDidEnterBackground(_ application: UIApplication) { scheduleRefresh() }

    func applicationDidBecomeActive(_ application: UIApplication) {
        application.applicationIconBadgeNumber = 0
        main.reloadData()
    }

    func scheduleRefresh() {
        let req = BGAppRefreshTaskRequest(identifier: refreshTaskId)
        req.earliestBeginDate = Date(timeIntervalSinceNow: 20 * 60)
        try? BGTaskScheduler.shared.submit(req)
    }

    func handleRefresh(_ task: BGAppRefreshTask) {
        scheduleRefresh()
        task.expirationHandler = { task.setTaskCompleted(success: false) }
        Scanner.checkNewLeads { ok in task.setTaskCompleted(success: ok) }
    }

    func application(_ application: UIApplication,
                     performFetchWithCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        Scanner.checkNewLeads { ok in completionHandler(ok ? .newData : .failed) }
    }

    // show banners while the app is open too
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .list])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        if let id = response.notification.request.content.userInfo["lead"] as? String, !id.isEmpty {
            main.openLead(id)
        }
        completionHandler()
    }
}

// MARK: - Screen
final class LeadViewController: UIViewController, WKScriptMessageHandler, WKNavigationDelegate, WKUIDelegate {
    private var webView: WKWebView!
    private let tap = UIImpactFeedbackGenerator(style: .light)
    private var base: String?
    private var pendingLead: String?
    private let refresher = UIRefreshControl()

    override func loadView() {
        let config = WKWebViewConfiguration()
        config.userContentController.add(self, name: "native")
        // tell the page it is running inside the iPhone app
        let js = "window.LF_NATIVE = true; window.LF_KEY = '\(Store.apiKey)';"
        config.userContentController.addUserScript(WKUserScript(source: js, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        config.websiteDataStore = .default()
        webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.isOpaque = false
        webView.backgroundColor = UIColor(red: 0.059, green: 0.078, blue: 0.102, alpha: 1)
        webView.scrollView.backgroundColor = webView.backgroundColor
        webView.allowsLinkPreview = false
        webView.allowsBackForwardNavigationGestures = false
        refresher.tintColor = UIColor(red: 0.94, green: 0.66, blue: 0.19, alpha: 1)
        refresher.addTarget(self, action: #selector(pulled), for: .valueChanged)
        webView.scrollView.refreshControl = refresher
        view = webView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        tap.prepare()
        connect()
    }

    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }

    @objc private func pulled() {
        if base == nil { connect() } else { webView.evaluateJavaScript("typeof load==='function'&&load()") { _, _ in } }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { self.refresher.endRefreshing() }
    }

    func connect() {
        showOffline(message: "NAS se jud raha hoon…")
        Scanner.findServer { [weak self] found in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if let b = found, let url = URL(string: b + "/") {
                    self.base = b
                    self.webView.load(URLRequest(url: url, cachePolicy: .reloadRevalidatingCacheData, timeoutInterval: 20))
                } else {
                    self.base = nil
                    self.showOffline(message: "Scanner (NAS) se connect nahi ho paya. Internet / office Wi-Fi check kijiye, ya neeche address theek kijiye.")
                }
            }
        }
    }

    func reloadData() {
        guard base != nil else { connect(); return }
        webView.evaluateJavaScript("typeof load==='function'&&load()") { _, _ in }
        // the app itself is open → move "last seen" forward so we don't notify for leads already visible
        Store.lastSeen = Date().timeIntervalSince1970
    }

    func openLead(_ id: String) {
        pendingLead = id
        webView.evaluateJavaScript("typeof openLeadById==='function'&&openLeadById('\(id)')") { r, _ in
            if (r as? Bool) == true { self.pendingLead = nil }
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
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "native", let body = message.body as? [String: Any], let type = body["t"] as? String else { return }
        switch type {
        case "haptic":
            tap.impactOccurred()
        case "open":
            if let s = body["url"] as? String, let url = URL(string: s) { openExternal(url) }
        case "notify-on":
            if let m = body["min"] as? Int { Store.minScore = m }
            Notify.ask { ok in
                self.webView.evaluateJavaScript("window.__notifyState && window.__notifyState(\(ok))") { _, _ in }
            }
        case "notify-state":
            UNUserNotificationCenter.current().getNotificationSettings { s in
                let ok = s.authorizationStatus == .authorized
                DispatchQueue.main.async {
                    self.webView.evaluateJavaScript("window.__notifyState && window.__notifyState(\(ok))") { _, _ in }
                }
            }
        case "settings":
            if let k = body["key"] as? String, !k.isEmpty { Store.apiKey = k }
            if let m = body["min"] as? Int { Store.minScore = m }
            if let s = body["servers"] as? [String] {
                let clean = s.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                    .map { $0.hasPrefix("http") ? $0 : "http://" + $0 }
                if !clean.isEmpty { Store.servers = clean }
            }
            if (body["reconnect"] as? Bool) == true { connect() }
        case "export":
            exportExcel()
        case "share":
            let text = body["text"] as? String ?? ""
            let vc = UIActivityViewController(activityItems: [text], applicationActivities: nil)
            vc.popoverPresentationController?.sourceView = view
            present(vc, animated: true)
        case "copy":
            UIPasteboard.general.string = body["text"] as? String ?? ""
            tap.impactOccurred()
        case "ready":
            if let id = pendingLead { openLead(id) }
        default:
            break
        }
    }

    private func openExternal(_ url: URL) {
        tap.impactOccurred()
        // WhatsApp: open the app directly when installed
        if url.host == "wa.me", let comps = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            let phone = url.path.replacingOccurrences(of: "/", with: "")
            let text = comps.queryItems?.first(where: { $0.name == "text" })?.value ?? ""
            var w = URLComponents(string: "whatsapp://send")!
            w.queryItems = [URLQueryItem(name: "phone", value: phone), URLQueryItem(name: "text", value: text)]
            if let wu = w.url, UIApplication.shared.canOpenURL(wu) {
                UIApplication.shared.open(wu); return
            }
        }
        UIApplication.shared.open(url)
    }

    private func exportExcel() {
        guard let b = base, let url = URL(string: b + "/export.xlsx") else { return }
        var req = URLRequest(url: url, timeoutInterval: 60)
        req.setValue(Store.apiKey, forHTTPHeaderField: "X-API-Key")
        URLSession.shared.dataTask(with: req) { data, resp, _ in
            guard let d = data, (resp as? HTTPURLResponse)?.statusCode == 200 else { return }
            let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
            let file = FileManager.default.temporaryDirectory.appendingPathComponent("AudioNation-Leads-\(f.string(from: Date())).xlsx")
            try? d.write(to: file)
            DispatchQueue.main.async {
                let vc = UIActivityViewController(activityItems: [file], applicationActivities: nil)
                vc.popoverPresentationController?.sourceView = self.view
                self.present(vc, animated: true)
            }
        }.resume()
    }

    // MARK: navigation — keep the app inside the NAS page; everything else opens outside
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else { decisionHandler(.cancel); return }
        let scheme = url.scheme?.lowercased() ?? ""
        if scheme == "file" || scheme == "about" { decisionHandler(.allow); return }
        if let b = base, let bh = URL(string: b)?.host, url.host == bh,
           scheme == "http" || scheme == "https" { decisionHandler(.allow); return }
        if navigationAction.navigationType == .other && navigationAction.targetFrame?.isMainFrame == true && base == nil {
            decisionHandler(.allow); return
        }
        decisionHandler(.cancel)
        openExternal(url)
    }

    // target=_blank links (WhatsApp, maps, listing pages)
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url { openExternal(url) }
        return nil
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if base != nil { Store.lastSeen = Date().timeIntervalSince1970 }
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        if base != nil { base = nil; showOffline(message: "NAS se connection toot gaya. Neeche 'Dobara jodiye' dabaiye.") }
    }

    // alert() / confirm() / prompt() from the page
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
