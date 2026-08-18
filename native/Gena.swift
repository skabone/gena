// Daybook — native macOS wrapper (WKWebView, no Electron, no dependencies)
// Required Notice: Copyright (c) 2026 Mintay Misgano (https://github.com/skabone)
// Licensed under the PolyForm Noncommercial License 1.0.0
//
// Loads the hosted Daybook so the app stays current and cloud sync works.
// The app keeps its own private storage, separate from any browser.

import Cocoa
import WebKit

let APP_URL = "https://skabone.github.io/daybook/"
let HOME_HOST = "skabone.github.io"

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

    override func viewDidLoad() {
        super.viewDidLoad()
        if let u = URL(string: APP_URL) { web.load(URLRequest(url: u)) }
    }

    @objc func reload(_ sender: Any?) { web.reload() }

    // Keep Daybook inside the app; send outside links to the real browser.
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
        window.title = "Daybook"
        window.contentViewController = controller
        window.setFrameAutosaveName("DaybookMainWindow")
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
    appMenu.addItem(withTitle: "About Daybook", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
    appMenu.addItem(.separator())
    appMenu.addItem(withTitle: "Hide Daybook", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
    let others = appMenu.addItem(withTitle: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
    others.keyEquivalentModifierMask = [.command, .option]
    appMenu.addItem(.separator())
    appMenu.addItem(withTitle: "Quit Daybook", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
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
