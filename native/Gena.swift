// Gena — native macOS wrapper (WKWebView, no Electron, no dependencies)
// Required Notice: Copyright (c) 2026 Mintay Misgano (https://github.com/skabone)
// Licensed under the PolyForm Noncommercial License 1.0.0
//
// Loads the hosted Gena so the app stays current and cloud sync works.
// The app keeps its own private storage, separate from any browser.

import Cocoa
import WebKit

let APP_URL = "https://skabone.github.io/gena/"
let HOME_HOST = "skabone.github.io"

let OFFLINE_HTML = """
<!doctype html><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>Gena</title>
<style>
  :root{ color-scheme: light dark; }
  body{ margin:0; min-height:100vh; display:flex; align-items:center; justify-content:center;
    font:16px/1.5 -apple-system, system-ui, sans-serif; background:Canvas; color:CanvasText; }
  main{ max-width:340px; padding:28px; text-align:center; }
  h1{ font-size:20px; margin:0 0 6px; }
  p{ margin:0 0 18px; opacity:.7; }
  a{ display:inline-block; padding:11px 20px; border-radius:12px; background:#9c7420; color:#fff;
    text-decoration:none; font-weight:600; }
</style>
<main><h1>Gena can’t be reached</h1>
<p>You’re offline, and this Mac has no saved copy yet. Your tasks are safe on this device — they’ll be here when Gena opens.</p>
<a href="\(APP_URL)">Try again</a></main>
"""

final class WebController: NSViewController, WKNavigationDelegate, WKUIDelegate {
    let web: WKWebView

    init() {
        let cfg = WKWebViewConfiguration()
        cfg.websiteDataStore = .default()          // persistent localStorage across launches
        cfg.defaultWebpagePreferences.allowsContentJavaScript = true
        self.web = WKWebView(frame: NSRect(x: 0, y: 0, width: 1200, height: 820), configuration: cfg)
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        web.navigationDelegate = self
        web.uiDelegate = self
        web.allowsBackForwardNavigationGestures = true
        self.view = web
    }

    // Revalidate rather than trusting the HTTP cache — GitHub Pages sends max-age=600, so a plain
    // load could show a build up to ten minutes old, and a long-running window far older than that.
    private var lastLoad = Date.distantPast

    func loadApp() {
        guard let u = URL(string: APP_URL) else { return }
        web.load(URLRequest(url: u, cachePolicy: .reloadRevalidatingCacheData, timeoutInterval: 30))
        lastLoad = Date()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        loadApp()
        // Coming back to the app after a while is the natural moment to pick up a push. Gated on five
        // minutes so switching windows mid-sentence never reloads under you.
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            if Date().timeIntervalSince(self.lastLoad) > 300 { self.loadApp() }
        }
    }

    @objc func reload(_ sender: Any?) { loadApp() }

    // Offline. Revalidating needs the network, so a failed load first retries from the cache — Gena is
    // local-first and the cached page is the whole app — and only then shows a page of its own instead
    // of WebKit's blank window. The page has no origin (baseURL nil), so it cannot touch Gena's storage.
    private var triedCache = false

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        let e = error as NSError
        if e.domain == NSURLErrorDomain && e.code == NSURLErrorCancelled { return }
        guard let u = URL(string: APP_URL) else { return }
        if !triedCache {
            triedCache = true
            web.load(URLRequest(url: u, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 15))
            return
        }
        triedCache = false
        web.loadHTMLString(OFFLINE_HTML, baseURL: nil)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if webView.url?.host == HOME_HOST { triedCache = false }
    }

    // Keep Gena inside the app; send outside links to the real browser.
    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if navigationAction.navigationType == .linkActivated,
           let u = navigationAction.request.url,
           let scheme = u.scheme, scheme.hasPrefix("http"),
           (u.host ?? "") != HOME_HOST {
            NSWorkspace.shared.open(u)
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    // target="_blank" / window.open → open externally instead of a dead popup
    func webView(_ webView: WKWebView,
                 createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction,
                 windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let u = navigationAction.request.url { NSWorkspace.shared.open(u) }
        return nil
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    var controller: WebController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        controller = WebController()
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1200, height: 820),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false)
        window.title = "Gena"
        window.contentViewController = controller
        window.setFrameAutosaveName("GenaMainWindow")
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    @objc func reload(_ sender: Any?) { controller?.reload(sender) }
}

func buildMenu(_ delegate: AppDelegate) -> NSMenu {
    let main = NSMenu()

    // App menu
    let appItem = NSMenuItem(); main.addItem(appItem)
    let appMenu = NSMenu()
    appMenu.addItem(withTitle: "About Gena", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
    appMenu.addItem(.separator())
    appMenu.addItem(withTitle: "Hide Gena", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
    let others = appMenu.addItem(withTitle: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
    others.keyEquivalentModifierMask = [.command, .option]
    appMenu.addItem(.separator())
    appMenu.addItem(withTitle: "Quit Gena", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    appItem.submenu = appMenu

    // Edit menu (makes Cmd+C/V/X/A + undo work in the web view)
    let editItem = NSMenuItem(); main.addItem(editItem)
    let editMenu = NSMenu(title: "Edit")
    editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
    let redo = editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
    redo.keyEquivalentModifierMask = [.command, .shift]
    editMenu.addItem(.separator())
    editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
    editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
    editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
    editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
    editItem.submenu = editMenu

    // View menu
    let viewItem = NSMenuItem(); main.addItem(viewItem)
    let viewMenu = NSMenu(title: "View")
    let reload = viewMenu.addItem(withTitle: "Reload", action: #selector(AppDelegate.reload(_:)), keyEquivalent: "r")
    reload.target = delegate
    viewItem.submenu = viewMenu

    // Window menu
    let winItem = NSMenuItem(); main.addItem(winItem)
    let winMenu = NSMenu(title: "Window")
    winMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
    winMenu.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
    winItem.submenu = winMenu
    NSApp.windowsMenu = winMenu

    return main
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)
let delegate = AppDelegate()
app.delegate = delegate
app.mainMenu = buildMenu(delegate)
app.run()
