import AppKit
import SwiftUI
import XCTest
@testable import LivePhotoStudio

final class AppAppearanceTests: XCTestCase {
    @MainActor func testExistingAndNewWindowsInheritManualAndSystemAppearance() {
        let application = NSApplication.shared
        let original = application.appearance
        defer { application.appearance = original }
        AppAppearance.system.apply(to: application)
        let system = application.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua])
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 100),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let host = NSHostingView(rootView: Text("Appearance inheritance"))
        window.contentView = host
        defer { window.close() }

        for mode in [AppAppearance.light, .system, .dark, .system, .light, .dark, .system] {
            mode.apply(to: application)
            let expected: NSAppearance.Name? = mode == .system ? system : mode == .light ? .aqua : .darkAqua
            XCTAssertEqual(application.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]), expected)
            XCTAssertNil(window.appearance, "The window must not pin a competing appearance")
            XCTAssertNil(host.appearance, "SwiftUI's host must inherit the native appearance")
            XCTAssertEqual(window.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]), expected)
            XCTAssertEqual(host.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]), expected)
            if mode == .system { XCTAssertNil(application.appearance) }

            let panel = NSPanel(contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: false)
            panel.isReleasedWhenClosed = false
            XCTAssertNil(panel.appearance)
            XCTAssertEqual(panel.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]), expected)
            panel.close()
        }
    }
}
