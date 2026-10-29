import XCTest
import WebKit
@testable import Wallnetic

final class WebWallpaperTests: XCTestCase {
    @MainActor
    func testDirectoryScanWinningImportRaceDoesNotDuplicateVideo() {
        let manager = WallpaperManager.shared
        let saved = manager.wallpapers
        defer { manager.wallpapers = saved }
        let url = URL(fileURLWithPath: "/tmp/wallnetic-import-race.mp4")
        let scanned = Wallpaper(url: url)
        manager.wallpapers = [scanned]
        let imported = manager.registerImportedWallpaper(Wallpaper(url: url))
        XCTAssertEqual(manager.wallpapers.count, 1)
        XCTAssertEqual(imported.id, scanned.id, "Keep the identity already shown by the directory watcher")
        manager.wallpapers = []
        let fresh = manager.registerImportedWallpaper(Wallpaper(url: url))
        XCTAssertEqual(manager.wallpapers.map(\.id), [fresh.id])
    }
    func testHTTPSAddressAndWhitespace() throws {
        XCTAssertEqual(try WebWallpaperSource.website(" https://example.com/scene ").url.absoluteString, "https://example.com/scene")
    }

    func testUnsafeAddressesRejected() {
        for value in ["", "example.com", "http://example.com", "javascript:alert(1)", "file:///etc/passwd", "https://user:secret@example.com", "https://"] {
            XCTAssertThrowsError(try WebWallpaperSource.website(value), value)
        }
    }

    func testLocalDocumentValidation() throws {
        XCTAssertTrue(try WebWallpaperSource.local(URL(fileURLWithPath: "/tmp/scene/index.HTML")).url.isFileURL)
        XCTAssertThrowsError(try WebWallpaperSource.local(URL(fileURLWithPath: "/tmp/scene.js")))
        XCTAssertThrowsError(try WebWallpaperSource.local(URL(string: "https://example.com/index.html")!))
    }

    func testPointerCoordinatesUseTopLeftOriginOnOffsetDisplay() {
        let display = CGRect(x: -1600, y: 200, width: 1600, height: 1000)
        let pointer = WebWallpaperPointer.normalized(CGPoint(x: -800, y: 450), in: display)
        XCTAssertEqual(pointer?.x, 0.5)
        XCTAssertEqual(pointer?.y, 0.75)
        XCTAssertNil(WebWallpaperPointer.normalized(CGPoint(x: 30, y: 400), in: display))
        XCTAssertNil(WebWallpaperPointer.normalized(.zero, in: .zero))
    }

    func testLocalNavigationCannotEscapeSelectedDirectory() throws {
        let source = try WebWallpaperSource.local(URL(fileURLWithPath: "/tmp/scene/index.html"))
        XCTAssertTrue(source.allowsNavigation(to: URL(fileURLWithPath: "/tmp/scene/page.html")))
        XCTAssertFalse(source.allowsNavigation(to: URL(fileURLWithPath: "/tmp/scene-evil/page.html")))
        XCTAssertFalse(source.allowsNavigation(to: URL(fileURLWithPath: "/tmp/scene/../secret.html")))
        XCTAssertFalse(source.allowsNavigation(to: URL(string: "https://example.com")!))
    }

    func testRemoteNavigationStaysOnOrigin() throws {
        let source = try WebWallpaperSource.website("https://example.com/scene")
        XCTAssertTrue(source.allowsNavigation(to: URL(string: "https://example.com/next")!))
        XCTAssertFalse(source.allowsNavigation(to: URL(string: "https://other.example")!))
        XCTAssertFalse(source.allowsNavigation(to: URL(string: "http://example.com")!))
        XCTAssertFalse(source.allowsNavigation(to: URL(string: "https://example.com:8443")!))
    }

    func testSourceRoundTripsWithoutLosingType() throws {
        let source = try WebWallpaperSource.website("https://example.com/scene")
        XCTAssertEqual(try JSONDecoder().decode(WebWallpaperSource.self, from: JSONEncoder().encode(source)), source)
    }

    func testPointerRejectsNonFiniteInput() {
        XCTAssertNil(WebWallpaperPointer.normalized(CGPoint(x: CGFloat.infinity, y: 1), in: CGRect(x: 0, y: 0, width: 100, height: 100)))
    }

    @MainActor
    func testPowerReleaseRespectsAutoResumeAndAllowsManualRecovery() throws {
        let domain = "WebWallpaperTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: domain)!
        let engine = WebWallpaperEngine(defaults: defaults)
        defer { engine.stop(); defaults.removePersistentDomain(forName: domain) }
        engine.setPowerPaused(true)
        try engine.apply(.orbit)
        engine.updatePowerCondition(paused: false, mayResume: false)
        XCTAssertTrue(engine.manuallyPaused)
        XCTAssertTrue(engine.webViews.isEmpty)
        engine.setPaused(false)
        XCTAssertTrue(engine.isRunning)
        engine.updatePowerCondition(paused: true, mayResume: true)
        XCTAssertTrue(engine.webViews.isEmpty)
        engine.updatePowerCondition(paused: false, mayResume: true)
        XCTAssertTrue(engine.isRunning)
    }

    @MainActor
    func testLoadingFailureCanBeRetried() async throws {
        let domain = "WebWallpaperTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: domain)!
        let engine = WebWallpaperEngine(defaults: defaults)
        defer { engine.stop(); defaults.removePersistentDomain(forName: domain) }
        try engine.apply(.orbit)
        let web = try await loadedWebView(engine)
        engine.webView(web, didFailProvisionalNavigation: nil, withError: URLError(.notConnectedToInternet))
        XCTAssertTrue(engine.manuallyPaused)
        XCTAssertFalse(engine.isRunning)
        XCTAssertTrue(engine.webViews.isEmpty)
        engine.setPaused(false)
        _ = try await loadedWebView(engine)
    }

    @MainActor
    func testBuiltInSceneLoadsReceivesPointerAndSuspendsCompletely() async throws {
        let domain = "WebWallpaperTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: domain)!
        let engine = WebWallpaperEngine(defaults: defaults)
        defer { engine.stop(); defaults.removePersistentDomain(forName: domain) }
        var changes: [Bool] = []
        engine.onPlaybackChange = { changes.append($0) }
        try engine.apply(.orbit)
        let web = try await loadedWebView(engine)
        let title = try await web.evaluateJavaScript("document.title") as? String
        XCTAssertEqual(title, "Orbit")
        try await web.evaluateJavaScript(WebWallpaperPointer.script(for: CGPoint(x: 0.25, y: 0.75)))
        let pointerX = try await web.evaluateJavaScript("window.lastWallpaperPointer.x") as? Double
        XCTAssertEqual(pointerX, 0.25)
        XCTAssertTrue(web.configuration.websiteDataStore.isPersistent == false)
        XCTAssertTrue(web.window?.ignoresMouseEvents == true)
        engine.pointerEnabled = false
        engine.sendPointer(.zero)
        engine.setPowerPaused(true)
        XCTAssertTrue(engine.webViews.isEmpty, "Power pause must unload JavaScript, not only pause media")
        XCTAssertFalse(engine.isRunning)
        engine.setPaused(true)
        engine.setPowerPaused(false)
        XCTAssertTrue(engine.webViews.isEmpty, "Power recovery must respect a manual pause")
        engine.setPaused(false)
        _ = try await loadedWebView(engine)
        XCTAssertTrue(engine.isRunning)
        engine.displayConfigurationChanged()
        _ = try await loadedWebView(engine)
        engine.stop()
        XCTAssertNil(engine.source)
        XCTAssertFalse(defaults.bool(forKey: "web.active"))
        XCTAssertEqual(changes.last, false)
    }

    @MainActor
    func testLocalHTMLAndRelativeAssetLoadAndInvalidReplacementPreservesScene() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let index = folder.appendingPathComponent("index.html")
        try "<html><title>Local scene</title><img src='star.svg'></html>".write(to: index, atomically: true, encoding: .utf8)
        try "<svg xmlns='http://www.w3.org/2000/svg' width='10' height='10'><rect width='10' height='10'/></svg>"
            .write(to: folder.appendingPathComponent("star.svg"), atomically: true, encoding: .utf8)
        let domain = "WebWallpaperTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: domain)!
        let engine = WebWallpaperEngine(defaults: defaults)
        defer { engine.stop(); defaults.removePersistentDomain(forName: domain); try? FileManager.default.removeItem(at: folder) }
        let source = try WebWallpaperSource.local(index)
        try engine.apply(source)
        let web = try await loadedWebView(engine)
        let title = try await web.evaluateJavaScript("document.title") as? String
        let imageWidth = try await web.evaluateJavaScript("document.querySelector('img').naturalWidth") as? Int
        XCTAssertEqual(title, "Local scene")
        XCTAssertEqual(imageWidth, 10)
        XCTAssertThrowsError(try engine.apply(.local(folder.appendingPathComponent("missing.html"))))
        XCTAssertEqual(engine.source, source)
        engine.webViewWebContentProcessDidTerminate(web)
        XCTAssertTrue(engine.manuallyPaused)
        XCTAssertTrue(engine.webViews.isEmpty)
    }

    @MainActor
    func testRestoreIsOptInAndKeepsPointerPreference() async throws {
        let domain = "WebWallpaperTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: domain)!
        let first = WebWallpaperEngine(defaults: defaults)
        defer { first.stop(); defaults.removePersistentDomain(forName: domain) }
        first.pointerEnabled = false
        first.setPowerPaused(true)
        try first.apply(.orbit)
        XCTAssertTrue(first.webViews.isEmpty)
        let second = WebWallpaperEngine(defaults: defaults)
        defer { second.stop() }
        second.restoreIfEnabled()
        XCTAssertNil(second.source)
        XCTAssertFalse(second.pointerEnabled)
        second.restoreAtLaunch = true
        second.restoreIfEnabled()
        _ = try await loadedWebView(second)
        XCTAssertEqual(second.source, .orbit)
    }

    @MainActor
    private func loadedWebView(_ engine: WebWallpaperEngine) async throws -> WKWebView {
        let deadline = Date().addingTimeInterval(8)
        while !engine.status.hasPrefix("Playing"), Date() < deadline {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertTrue(engine.status.hasPrefix("Playing"), engine.status)
        return try XCTUnwrap(engine.webViews.values.first)
    }
}
