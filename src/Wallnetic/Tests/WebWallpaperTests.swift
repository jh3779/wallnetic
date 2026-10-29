import XCTest
@testable import Wallnetic

final class WebWallpaperTests: XCTestCase {
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
}
