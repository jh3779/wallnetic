import Cocoa
import WebKit
import SwiftUI

/// Main-thread UI service, like DesktopWindowController. Hosts content below Finder's icons.
final class WebWallpaperEngine: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate {
    static let shared = WebWallpaperEngine()
    @Published private(set) var source: WebWallpaperSource?
    @Published private(set) var status = "No web wallpaper is running"
    @Published private(set) var manuallyPaused = false
    @Published var pointerEnabled: Bool { didSet { defaults.set(pointerEnabled, forKey: "web.pointer"); updatePointerTimer() } }
    @Published var restoreAtLaunch: Bool { didSet { defaults.set(restoreAtLaunch, forKey: "web.restore") } }
    var onActivate: (() -> Void)?
    var onPlaybackChange: ((Bool) -> Void)?

    private let defaults: UserDefaults
    private var windows: [CGDirectDisplayID: NSWindow] = [:]
    private(set) var webViews: [CGDirectDisplayID: WKWebView] = [:]
    private var timer: Timer?
    private var scopedFolder: URL?
    private var powerPaused = false
    private var pendingPointer = Set<CGDirectDisplayID>()
    private var lastPointer: [CGDirectDisplayID: CGPoint] = [:]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        pointerEnabled = defaults.object(forKey: "web.pointer") as? Bool ?? true
        restoreAtLaunch = defaults.bool(forKey: "web.restore")
        super.init()
    }

    var isRunning: Bool { source != nil && !manuallyPaused && !powerPaused }

    func apply(_ requested: WebWallpaperSource) throws {
        var next = requested
        var newScopedFolder: URL?
        var installed = false
        defer { if !installed { newScopedFolder?.stopAccessingSecurityScopedResource() } }
        if next.kind == .website { next = try .website(next.url.absoluteString) }
        if next.kind == .local {
            next = try .local(next.url)
            next.folderBookmark = requested.folderBookmark
        }
        if let bookmark = next.folderBookmark {
            var stale = false
            let folder = try URL(resolvingBookmarkData: bookmark, options: .withSecurityScope, bookmarkDataIsStale: &stale)
            if folder.startAccessingSecurityScopedResource() { newScopedFolder = folder }
            next = try WebWallpaperSource.local(folder.appendingPathComponent(next.url.lastPathComponent))
            guard next.url.path.hasPrefix(folder.resolvingSymlinksInPath().standardizedFileURL.path + "/") else {
                throw WebWallpaperSource.SourceError.document
            }
            next.folderBookmark = try folder.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess])
        }
        if next.kind == .local && !FileManager.default.fileExists(atPath: next.url.path) {
            throw WebWallpaperSource.SourceError.missingIndex
        }
        shutdown()
        scopedFolder = newScopedFolder
        installed = true
        onActivate?()
        source = next
        manuallyPaused = false
        defaults.set(try JSONEncoder().encode(next), forKey: "web.source")
        defaults.set(true, forKey: "web.active")
        if !powerPaused { buildWindows() } else { status = "Paused to save power" }
        onPlaybackChange?(isRunning)
    }

    func restoreIfEnabled() {
        guard restoreAtLaunch, defaults.bool(forKey: "web.active"),
              let data = defaults.data(forKey: "web.source"),
              let saved = try? JSONDecoder().decode(WebWallpaperSource.self, from: data) else { return }
        do { try apply(saved) } catch { status = error.localizedDescription }
    }

    func stop() {
        shutdown()
        source = nil
        manuallyPaused = false
        defaults.set(false, forKey: "web.active")
        status = "No web wallpaper is running"
        onPlaybackChange?(false)
    }

    func setPaused(_ paused: Bool) {
        manuallyPaused = paused
        refreshPlayback()
    }

    func setPowerPaused(_ paused: Bool) {
        guard powerPaused != paused else { return }
        powerPaused = paused
        refreshPlayback()
    }

    func updatePowerCondition(paused: Bool, mayResume: Bool) {
        if powerPaused && !paused && !mayResume && source != nil { manuallyPaused = true }
        setPowerPaused(paused)
    }

    func displayConfigurationChanged() {
        guard isRunning else { return }
        tearDownWindows()
        buildWindows()
    }

    func shutdown() {
        tearDownWindows()
        scopedFolder?.stopAccessingSecurityScopedResource()
        scopedFolder = nil
    }

    private func refreshPlayback() {
        guard source != nil else { return }
        if isRunning {
            if webViews.isEmpty { buildWindows() }
        } else {
            // Unload the document as well as media: arbitrary JS timers must not keep running.
            tearDownWindows()
            status = powerPaused ? "Paused to save power · resumes automatically" : "Paused · the system wallpaper is visible"
        }
        onPlaybackChange?(isRunning)
    }

    private func buildWindows() {
        guard let source else { return }
        status = "Loading \(source.title)…"
        for screen in NSScreen.screens {
            guard let id = screen.displayID else { continue }
            let config = WKWebViewConfiguration()
            config.websiteDataStore = .nonPersistent()
            config.preferences.javaScriptCanOpenWindowsAutomatically = false
            config.mediaTypesRequiringUserActionForPlayback = .all
            let web = WKWebView(frame: NSRect(origin: .zero, size: screen.frame.size), configuration: config)
            web.navigationDelegate = self
            web.uiDelegate = self
            web.autoresizingMask = [.width, .height]
            web.underPageBackgroundColor = .black
            let window = OverlayWindowFactory.makeBackgroundWindow(contentRect: screen.frame)
            window.level = .init(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) - 1)
            window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]
            window.ignoresMouseEvents = true
            window.animationBehavior = .none
            window.contentView = web
            windows[id] = window
            webViews[id] = web
            switch source.kind {
            case .website: web.load(URLRequest(url: source.url, timeoutInterval: 30))
            case .local: web.loadFileURL(source.url, allowingReadAccessTo: source.url.deletingLastPathComponent())
            case .builtIn: web.loadHTMLString(OrbitWallpaper.html, baseURL: nil)
            }
        }
        updatePointerTimer()
    }

    private func tearDownWindows() {
        timer?.invalidate(); timer = nil
        for web in webViews.values {
            web.navigationDelegate = nil; web.uiDelegate = nil
            web.stopLoading()
            web.loadHTMLString("", baseURL: nil)
            web.removeFromSuperview()
        }
        for window in windows.values { window.close() }
        webViews.removeAll(); windows.removeAll()
        pendingPointer.removeAll(); lastPointer.removeAll()
    }

    private func updatePointerTimer() {
        timer?.invalidate(); timer = nil
        guard pointerEnabled, isRunning, !webViews.isEmpty else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.sendPointer(NSEvent.mouseLocation) }
        }
        timer?.tolerance = 0.01
    }

    func sendPointer(_ location: CGPoint) {
        guard pointerEnabled, isRunning else { return }
        for screen in NSScreen.screens {
            guard let id = screen.displayID, let web = webViews[id],
                  let point = WebWallpaperPointer.normalized(location, in: screen.frame),
                  point != lastPointer[id], !pendingPointer.contains(id) else { continue }
            lastPointer[id] = point
            pendingPointer.insert(id)
            web.evaluateJavaScript(WebWallpaperPointer.script(for: point)) { [weak self, weak web] _, _ in
                guard let self, self.webViews[id] === web else { return }
                self.pendingPointer.remove(id)
            }
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard let entry = webViews.first(where: { $0.value === webView }), isRunning else { return }
        windows[entry.key]?.orderFrontRegardless()
        status = "Playing \(source?.title ?? "web wallpaper")"
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        let allowed = navigationAction.targetFrame != nil
            && navigationAction.request.url.map { source?.allowsNavigation(to: $0) ?? false } == true
        decisionHandler(allowed ? .allow : .cancel)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        guard (error as NSError).code != NSURLErrorCancelled else { return }
        tearDownWindows()
        manuallyPaused = true
        status = "Could not load this background: \(error.localizedDescription)"
        onPlaybackChange?(false)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        self.webView(webView, didFailProvisionalNavigation: navigation, withError: error)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        tearDownWindows()
        manuallyPaused = true
        status = "Web content stopped. Choose Resume to reload it."
        onPlaybackChange?(false)
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? { nil }
    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) { completionHandler() }
    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) { completionHandler(false) }
    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (String?) -> Void) { completionHandler(nil) }
    func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                 initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType,
                 decisionHandler: @escaping (WKPermissionDecision) -> Void) { decisionHandler(.deny) }
}
