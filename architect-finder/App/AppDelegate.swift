import UIKit
import WebKit
import CoreLocation

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = FinderViewController()
        window.backgroundColor = UIColor(red: 0.063, green: 0.137, blue: 0.247, alpha: 1)
        window.makeKeyAndVisible()
        self.window = window
        return true
    }
}

/// Shows the bundled web app and gives it three native abilities:
/// the iPhone's location, Google Places requests (no browser CORS limits),
/// and opening phone calls / maps / websites.
final class FinderViewController: UIViewController, WKScriptMessageHandler, CLLocationManagerDelegate {
    private var webView: WKWebView!
    private let manager = CLLocationManager()
    private var wantsLocation = false
    private let tap = UIImpactFeedbackGenerator(style: .light)

    override func loadView() {
        let config = WKWebViewConfiguration()
        config.userContentController.add(self, name: "native")
        webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = UIColor(red: 0.957, green: 0.937, blue: 0.894, alpha: 1)
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.scrollView.backgroundColor = webView.backgroundColor
        webView.allowsLinkPreview = false
        view = webView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        tap.prepare()
        if let url = Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "web") {
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        }
    }

    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }

    // MARK: messages from the page
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "native", let body = message.body as? [String: Any], let type = body["t"] as? String else { return }
        switch type {
        case "haptic":
            tap.impactOccurred()
        case "open":
            if let s = body["url"] as? String, let url = URL(string: s) { UIApplication.shared.open(url) }
        case "loc":
            requestLocation()
        case "fetch":
            runFetch(body)
        case "findnas":
            findNas()
        case "copy":
            UIPasteboard.general.string = body["text"] as? String ?? ""
            tap.impactOccurred()
        default:
            break
        }
    }

    // MARK: AN Search — look for the NAS (port 8856) on this Wi-Fi network
    private func wifiAddress() -> String? {
        var found: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return nil }
        var p: UnsafeMutablePointer<ifaddrs>? = first
        while let a = p {
            let flags = Int32(truncatingIfNeeded: a.pointee.ifa_flags)
            if let sa = a.pointee.ifa_addr, sa.pointee.sa_family == UInt8(AF_INET), (flags & IFF_LOOPBACK) == 0, (flags & IFF_UP) != 0 {
                var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(sa, socklen_t(sa.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                    let ip = String(cString: host)
                    let name = String(cString: a.pointee.ifa_name)
                    let priv = ip.hasPrefix("192.168.") || ip.hasPrefix("10.") || ip.hasPrefix("172.")
                    if priv && (name == "en0" || found == nil) { found = ip }
                }
            }
            p = a.pointee.ifa_next
        }
        freeifaddrs(ifaddr)
        return found
    }

    private func findNas() {
        guard let me = wifiAddress() else { replyFind(""); return }
        let prefix = me.split(separator: ".").prefix(3).joined(separator: ".")
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 2
        cfg.timeoutIntervalForResource = 3
        let session = URLSession(configuration: cfg)
        let group = DispatchGroup()
        let lock = NSLock()
        var hit: String?
        for i in 1...254 {
            let base = "http://\(prefix).\(i):8856"
            guard let url = URL(string: base + "/health") else { continue }
            group.enter()
            session.dataTask(with: url) { data, _, _ in
                defer { group.leave() }
                guard let d = data, let j = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any],
                      j["version"] != nil, j["searxng"] != nil else { return }
                lock.lock(); if hit == nil { hit = base }; lock.unlock()
            }.resume()
        }
        group.notify(queue: .main) { [weak self] in
            session.finishTasksAndInvalidate()
            self?.replyFind(hit ?? "")
        }
    }

    private func replyFind(_ url: String) {
        DispatchQueue.main.async { [weak self] in
            self?.webView.evaluateJavaScript("window.__nfind('\(url)')", completionHandler: nil)
        }
    }

    // MARK: Google Places request done natively
    private func runFetch(_ b: [String: Any]) {
        guard let id = b["id"] as? Int, let s = b["url"] as? String, let url = URL(string: s) else { return }
        var req = URLRequest(url: url, timeoutInterval: 20)
        if (b["method"] as? String) == "GET" {
            req.timeoutInterval = 10
            req.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")
            URLSession.shared.dataTask(with: req) { [weak self] data, resp, err in
                let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
                let raw = data ?? Data((err?.localizedDescription ?? "").utf8)
                let text = raw.prefix(600_000)
                let b64 = text.base64EncodedString()
                DispatchQueue.main.async {
                    self?.webView.evaluateJavaScript("window.__nf(\(id),\(status),'\(b64)')", completionHandler: nil)
                }
            }.resume()
            return
        }
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(b["key"] as? String ?? "", forHTTPHeaderField: "X-Goog-Api-Key")
        req.setValue(b["mask"] as? String ?? "", forHTTPHeaderField: "X-Goog-FieldMask")
        // lets the key be restricted to this app in Google Cloud
        req.setValue(Bundle.main.bundleIdentifier ?? "", forHTTPHeaderField: "X-Ios-Bundle-Identifier")
        req.httpBody = (b["body"] as? String)?.data(using: .utf8)
        URLSession.shared.dataTask(with: req) { [weak self] data, resp, err in
            let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
            let text = data ?? Data((err?.localizedDescription ?? "").utf8)
            let b64 = text.base64EncodedString()
            DispatchQueue.main.async {
                self?.webView.evaluateJavaScript("window.__nf(\(id),\(status),'\(b64)')", completionHandler: nil)
            }
        }.resume()
    }

    // MARK: location
    private func requestLocation() {
        wantsLocation = true
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            sendLocation(nil, "Location permission is off. Turn it on in iPhone Settings > Privacy > Location Services > AN Architects.")
        default:
            manager.requestLocation()
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard wantsLocation else { return }
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways: manager.requestLocation()
        case .denied, .restricted: sendLocation(nil, "Location permission is off. Turn it on in iPhone Settings > Privacy > Location Services > AN Architects.")
        default: break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard wantsLocation, let l = locations.last else { return }
        sendLocation(l.coordinate, nil)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        guard wantsLocation else { return }
        sendLocation(nil, "Could not get your location. Try again outdoors or near a window.")
    }

    private func sendLocation(_ c: CLLocationCoordinate2D?, _ err: String?) {
        wantsLocation = false
        let js: String
        if let c = c { js = "window.__nloc(\(c.latitude),\(c.longitude),null)" }
        else { js = "window.__nloc(0,0,'\((err ?? "").replacingOccurrences(of: "'", with: "\\'"))')" }
        webView.evaluateJavaScript(js, completionHandler: nil)
    }
}
