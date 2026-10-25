import UIKit
import WebKit
import AVFoundation

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // Game sounds mix with music and respect the silent switch.
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)

        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = GameViewController()
        window.backgroundColor = UIColor(red: 0.03, green: 0.07, blue: 0.16, alpha: 1)
        window.makeKeyAndVisible()
        self.window = window
        return true
    }

    // Reopening the app (from the app switcher, or after a call/notification)
    // leaves the audio session inactive even though the page's own AudioContext
    // thinks it is running, which is why sound would stay silent until a fresh
    // launch. Reactivating it here brings sound back as soon as the game is visible again.
    func applicationDidBecomeActive(_ application: UIApplication) {
        try? AVAudioSession.sharedInstance().setActive(true)
    }
}

/// Hosts the Ludo game (web/index.html, bundled inside the app) and turns
/// "haptic" messages from the game into real iPhone vibrations.
final class GameViewController: UIViewController, WKScriptMessageHandler {
    private var webView: WKWebView!
    private let light = UIImpactFeedbackGenerator(style: .light)
    private let medium = UIImpactFeedbackGenerator(style: .medium)
    private let heavy = UIImpactFeedbackGenerator(style: .heavy)
    private let notify = UINotificationFeedbackGenerator()

    override func loadView() {
        let config = WKWebViewConfiguration()
        config.userContentController.add(self, name: "haptic")
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []

        webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = UIColor(red: 0.03, green: 0.07, blue: 0.16, alpha: 1)
        webView.scrollView.backgroundColor = webView.backgroundColor
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.allowsLinkPreview = false
        view = webView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        light.prepare()
        medium.prepare()
        if let url = Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "web") {
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        }
    }

    override var prefersStatusBarHidden: Bool { true }
    override var prefersHomeIndicatorAutoHidden: Bool { true }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .portrait }

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        guard message.name == "haptic" else { return }
        switch message.body as? String ?? "light" {
        case "medium": medium.impactOccurred()
        case "heavy": heavy.impactOccurred()
        case "success": notify.notificationOccurred(.success)
        case "error": notify.notificationOccurred(.error)
        default: light.impactOccurred()
        }
    }
}
