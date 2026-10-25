import UIKit
import WebKit

/// 👋 "Send my contact" — opens the forum post inside the app (same login as before, saved in the app)
/// and sends the poster a PRIVATE message with Audio Nation's details:
///   • HiFiVision / AVS Forum / Home Theater Forum (XenForo): finds who wrote the post, opens
///     "Start conversation" to that person, fills title + message, presses the send button.
///   • Reddit: opens the message form to the poster with everything filled, presses Send.
///   • Other sites: opens the post; the message is already copied — paste and send.
/// The page stays visible the whole time, so you see exactly what is sent.
final class AutoSendController: UIViewController, WKNavigationDelegate, WKScriptMessageHandler {
    private let startURL: URL
    private let message: String
    private let subject: String
    private let leadId: String
    private let onSent: (String) -> Void

    private var webView: WKWebView!
    private let status = UILabel()
    private let bar = UIView()
    private var submitted = false
    private var finished = false
    private let haptic = UINotificationFeedbackGenerator()

    init(url: URL, message: String, title: String, leadId: String, onSent: @escaping (String) -> Void) {
        startURL = url; self.message = message; subject = title; self.leadId = leadId; self.onSent = onSent
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        let cfg = WKWebViewConfiguration()
        cfg.websiteDataStore = .default()                 // logins stay saved inside the app
        cfg.userContentController.add(WeakHandler(self), name: "auto")
        webView = WKWebView(frame: .zero, configuration: cfg)
        webView.navigationDelegate = self
        webView.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"

        let root = UIView()
        root.backgroundColor = .systemBackground
        bar.backgroundColor = UIColor(red: 0.94, green: 0.66, blue: 0.19, alpha: 1)
        status.font = .systemFont(ofSize: 15, weight: .semibold)
        status.textColor = UIColor(red: 0.1, green: 0.07, blue: 0, alpha: 1)
        status.numberOfLines = 0
        status.text = "👋 Opening the post…"
        let views: [UIView] = [bar, webView]
        for v in views { v.translatesAutoresizingMaskIntoConstraints = false; root.addSubview(v) }
        status.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(status)
        NSLayoutConstraint.activate([
            bar.topAnchor.constraint(equalTo: root.safeAreaLayoutGuide.topAnchor),
            bar.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            status.topAnchor.constraint(equalTo: bar.topAnchor, constant: 10),
            status.bottomAnchor.constraint(equalTo: bar.bottomAnchor, constant: -10),
            status.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 14),
            status.trailingAnchor.constraint(equalTo: bar.trailingAnchor, constant: -14),
            webView.topAnchor.constraint(equalTo: bar.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: root.bottomAnchor),
        ])
        view = root
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Send my contact"
        navigationItem.leftBarButtonItem = UIBarButtonItem(title: "‹ Back", style: .plain, target: self, action: #selector(close))
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Copy msg", style: .plain, target: self, action: #selector(copyMsg))
        haptic.prepare()
        webView.load(URLRequest(url: startURL))
    }

    @objc private func close() { dismiss(animated: true) }
    @objc private func copyMsg() { UIPasteboard.general.string = message; say("📋 Message copied — paste it in the reply box.") }

    private func say(_ t: String, color: UIColor? = nil) {
        status.text = t
        bar.backgroundColor = color ?? UIColor(red: 0.94, green: 0.66, blue: 0.19, alpha: 1)
    }

    // MARK: page automation
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard !finished else { return }
        let js = Self.script(message: message, title: subject, submitted: submitted)
        webView.evaluateJavaScript(js) { _, _ in }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        if (error as NSError).code != NSURLErrorCancelled { say("⚠️ Page did not load. Check internet and tap Back.", color: .systemRed) }
    }

    func userContentController(_ uc: WKUserContentController, didReceive m: WKScriptMessage) {
        guard let b = m.body as? [String: Any], let s = b["s"] as? String else { return }
        switch s {
        case "opening":
            say("👋 Found the poster \(b["name"] as? String ?? "") — opening a private message…")
        case "filling":
            say("✍️ Writing your message…")
        case "sending":
            submitted = true
            say("📨 Sending…")
        case "sent":
            finished = true
            haptic.notificationOccurred(.success)
            say("✅ Sent! Your message and numbers reached the poster.", color: UIColor(red: 0.24, green: 0.77, blue: 0.43, alpha: 1))
            onSent(leadId)
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in self?.dismiss(animated: true) }
        case "login":
            say("🔑 Please log in to this forum here once (it stays saved). Then tap Back and tap 👋 again.")
        case "error":
            finished = true
            haptic.notificationOccurred(.error)
            say("⚠️ The forum said: \(b["text"] as? String ?? "could not send"). The message is copied — you can paste it as a reply.", color: .systemRed)
        case "manual":
            finished = true
            say("📋 This site can't be sent automatically. Message is copied — tap Reply on the page, paste, and Send.")
        default:
            break
        }
    }

    /// JavaScript that runs on each page load inside the sheet.
    static func script(message: String, title: String, submitted: Bool) -> String {
        func js(_ s: String) -> String {
            let d = try! JSONSerialization.data(withJSONObject: [s])
            return String(String(data: d, encoding: .utf8)!.dropFirst().dropLast())
        }
        return """
        (function(){
          const MSG=\(js(message)), TITLE=\(js(title)), SUBMITTED=\(submitted ? "true" : "false");
          const post=o=>window.webkit.messageHandlers.auto.postMessage(o);
          const host=location.hostname, path=location.pathname;
          const $=s=>document.querySelector(s);
          const errBox=()=>{const e=$('.blockMessage--error, .formRow-explain--error, .overlay .blockMessage');return e&&e.offsetParent?e.textContent.trim().slice(0,140):''};
          // ---------- XenForo forums (HiFiVision, AVS Forum, Home Theater Forum)
          if($('html[data-app="public"]') || document.documentElement.id==='XF' || $('[data-xf-init]')){
            if($('form[action*="login"] input[type="password"]') && !$('a[href*="/account/"]')){post({s:'login'});return;}
            if(/\\/conversations\\/add/.test(path)){
              if(SUBMITTED){const e=errBox(); if(e){post({s:'error',text:e});return;}}
              post({s:'filling'});
              const t=$('input[name="title"]'); if(t&&!t.value)t.value=TITLE;
              const html=MSG.split('\\n').map(l=>'<p>'+(l?l.replace(/&/g,'&amp;').replace(/</g,'&lt;'):'<br>')+'</p>').join('');
              const fill=()=>{
                const ed=$('.fr-element[contenteditable="true"]');
                if(ed){ed.innerHTML=html;ed.dispatchEvent(new Event('input',{bubbles:true}));ed.dispatchEvent(new Event('keyup',{bubbles:true}));}
                const ta=$('textarea[name="message_html"]')||$('textarea[name="message"]');
                if(ta){ta.value=ed?html:MSG;ta.dispatchEvent(new Event('input',{bubbles:true}));}
                const btn=$('form[action*="conversations"] button[type="submit"]')||$('.formSubmitRow-controls button[type="submit"]');
                if(!btn){post({s:'error',text:'send button not found'});return;}
                post({s:'sending'});
                btn.click();
                // XenForo sends by AJAX: watch for success (redirect) or an error box
                let n=0;const w=setInterval(()=>{n++;const e=errBox();
                  if(e){clearInterval(w);post({s:'error',text:e});}
                  else if(!/\\/conversations\\/add/.test(location.pathname)){clearInterval(w);post({s:'sent'});}
                  else if(n>40){clearInterval(w);post({s:'error',text:'no reply from forum'});}},300);
              };
              setTimeout(fill, 1200);   // let the editor start
              return;
            }
            if(/\\/conversations\\/[^\\/]+\\.\\d+/.test(path) && SUBMITTED){post({s:'sent'});return;}
            // thread page: who wrote the first post?
            const op=$('.message--post .message-name .username')||$('article.message .message-name a')||$('.message-userDetails .username');
            const name=op?op.textContent.trim():'';
            if(name){post({s:'opening',name});location.href=location.origin+'/conversations/add?to='+encodeURIComponent(name)+'&title='+encodeURIComponent(TITLE);return;}
            post({s:'manual'});return;
          }
          // ---------- Reddit (old.reddit compose form, pre-filled by the URL)
          if(/reddit\\.com$/.test(host)){
            if(/\\/login/.test(path) || $('form#login-form') ){post({s:'login'});return;}
            if(/\\/message\\/compose/.test(path)){
              if(SUBMITTED){const ok=$('.status')&&/sent|delivered/i.test($('.status').textContent);post(ok?{s:'sent'}:{s:'error',text:($('.error')||{}).textContent||'not sent'});return;}
              const btn=$('form#compose-message button[type="submit"]')||$('#send');
              if(!btn){post({s:'manual'});return;}
              post({s:'sending'});btn.click();
              let n=0;const w=setInterval(()=>{n++;const st=$('.status');
                if(st&&/sent|delivered/i.test(st.textContent)){clearInterval(w);post({s:'sent'});}
                else if(n>30){clearInterval(w);post({s:'error',text:(($('.error:not([style*="none"])')||{}).textContent||'not sent').trim().slice(0,140)});}},300);
              return;
            }
            post({s:'manual'});return;
          }
          post({s:'manual'});
        })();
        """
    }
}

/// Avoids a retain cycle between WKUserContentController and the controller.
final class WeakHandler: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?
    init(_ t: WKScriptMessageHandler) { target = t }
    func userContentController(_ uc: WKUserContentController, didReceive m: WKScriptMessage) {
        target?.userContentController(uc, didReceive: m)
    }
}
