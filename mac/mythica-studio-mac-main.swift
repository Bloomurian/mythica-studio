// Mythica Studio — a small native macOS app (AppKit + WKWebView). No Chrome, no dependencies.
// Built by build-mythica-studio-mac-app.command with Apple's swiftc.
// The page (app/mythica-studio.html) is bundled inside the app. Your story is saved to
// ~/Documents/Mythica Studio/mythica-studio-data.json (daily copies in backups/), exports go to exports/.
import Cocoa
import WebKit

let kTitle = "Mythica Studio"

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
    var window: NSWindow!
    var web: WKWebView!

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMenu()
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Mythica Studio")
        try? FileManager.default.createDirectory(at: docs, withIntermediateDirectories: true)
        Mythica.shared.dir = docs

        let cfg = WKWebViewConfiguration()
        cfg.websiteDataStore = .default()
        cfg.userContentController.add(self, name: "mythica")
        cfg.setURLSchemeHandler(MythMedia.shared, forURLScheme: "mythmedia")
        cfg.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
        cfg.preferences.setValue(true, forKey: "developerExtrasEnabled")
        if #available(macOS 12.3, *) { cfg.preferences.isElementFullscreenEnabled = true }

        let frame = NSRect(x: 0, y: 0, width: 1400, height: 900)
        web = WKWebView(frame: frame, configuration: cfg)
        web.navigationDelegate = self
        web.uiDelegate = self
        web.autoresizingMask = [.width, .height]
        web.setValue(false, forKey: "drawsBackground")
        Mythica.shared.web = web

        window = NSWindow(contentRect: frame, styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = kTitle
        window.backgroundColor = NSColor(srgbRed: 0.016, green: 0.067, blue: 0.047, alpha: 1)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = web
        if !window.setFrameUsingName("MythicaStudioMain") { window.center() }
        window.setFrameAutosaveName("MythicaStudioMain")
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        guard let html = Bundle.main.url(forResource: "mythica-studio", withExtension: "html") else {
            let a = NSAlert(); a.messageText = "mythica-studio.html is missing from the app"; a.informativeText = "Run build-mythica-studio-mac-app.command again."; a.runModal()
            NSApp.terminate(nil); return
        }
        web.loadFileURL(html, allowingReadAccessTo: html.deletingLastPathComponent())
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    // messages from the page
    func userContentController(_ ucc: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let s = message.body as? String, let d = s.data(using: .utf8),
              let o = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] else { return }
        if o["myth"] != nil { Mythica.shared.handle(o, frame: message.frameInfo) }
    }

    // links open in the default browser; the app itself stays on the bundled page
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = action.request.url else { decisionHandler(.allow); return }
        let scheme = (url.scheme ?? "").lowercased()
        if ["about", "data", "blob", "file", "mythmedia"].contains(scheme) { decisionHandler(.allow); return }
        NSWorkspace.shared.open(url); decisionHandler(.cancel)
    }
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = action.request.url { NSWorkspace.shared.open(url) }
        return nil
    }
    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        let a = NSAlert(); a.messageText = kTitle; a.informativeText = message; a.runModal(); completionHandler()
    }
    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        let a = NSAlert(); a.messageText = kTitle; a.informativeText = message; a.addButton(withTitle: "OK"); a.addButton(withTitle: "Cancel")
        completionHandler(a.runModal() == .alertFirstButtonReturn)
    }
    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (String?) -> Void) {
        let a = NSAlert(); a.messageText = prompt
        let f = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24)); f.stringValue = defaultText ?? ""
        a.accessoryView = f; a.addButton(withTitle: "OK"); a.addButton(withTitle: "Cancel"); a.window.initialFirstResponder = f
        completionHandler(a.runModal() == .alertFirstButtonReturn ? f.stringValue : nil)
    }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { webView.reload() }

    @objc func reloadPage(_ sender: Any?) { web.reload() }
    @objc func openStoryFolder(_ sender: Any?) { if let d = Mythica.shared.dir { NSWorkspace.shared.open(d) } }

    func buildMenu() {
        let main = NSMenu()
        func add(_ title: String, _ items: [NSMenuItem]) -> NSMenu {
            let top = NSMenuItem(); let m = NSMenu(title: title); items.forEach { m.addItem($0) }; top.submenu = m; main.addItem(top); return m
        }
        func item(_ t: String, _ a: Selector?, _ k: String, _ mods: NSEvent.ModifierFlags = [.command], target: AnyObject? = nil) -> NSMenuItem {
            let i = NSMenuItem(title: t, action: a, keyEquivalent: k); i.keyEquivalentModifierMask = mods; if let target = target { i.target = target }; return i
        }
        _ = add(kTitle, [
            item("About \(kTitle)", #selector(NSApplication.orderFrontStandardAboutPanel(_:)), ""),
            .separator(),
            item("Open Story Folder", #selector(openStoryFolder(_:)), "", target: self),
            .separator(),
            item("Hide \(kTitle)", #selector(NSApplication.hide(_:)), "h"),
            item("Quit \(kTitle)", #selector(NSApplication.terminate(_:)), "q")])
        _ = add("Edit", [
            item("Undo", Selector(("undo:")), "z"), item("Redo", Selector(("redo:")), "z", [.command, .shift]), .separator(),
            item("Cut", #selector(NSText.cut(_:)), "x"), item("Copy", #selector(NSText.copy(_:)), "c"),
            item("Paste", #selector(NSText.paste(_:)), "v"), item("Select All", #selector(NSText.selectAll(_:)), "a")])
        _ = add("View", [
            item("Reload", #selector(reloadPage(_:)), "r", target: self),
            item("Toggle Full Screen", #selector(NSWindow.toggleFullScreen(_:)), "f", [.command, .control])])
        let w = add("Window", [
            item("Minimize", #selector(NSWindow.performMiniaturize(_:)), "m"),
            item("Zoom", #selector(NSWindow.performZoom(_:)), "")])
        NSApp.mainMenu = main
        NSApp.windowsMenu = w
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
