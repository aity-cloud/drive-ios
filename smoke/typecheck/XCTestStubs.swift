//
// XCTestStubs.swift
// Aity Drive iOS Factory - Linux type-check harness for the smoke sources.
//
// NOT SHIPPED, NOT part of the smoke target. `scripts/check-smoke-swift.sh`
// compiles smoke/AityDriveSmokeUITests/*.swift against these stubs with
// `swiftc -typecheck` on Linux, where XCTest's UI-testing half does not
// exist.
//
// WHY. Every mistake in the smoke sources otherwise costs a full round trip
// on the `macos` runner - which is Raul's laptop, one job at a time. A single
// "cannot find 'clear' in scope" burned one on 2026-08-27, and `swiftc
// -parse` cannot see that class of error because it never resolves names.
//
// WHAT IT IS AND IS NOT. It checks that every name resolves and every call
// has plausible arity and types. It is NOT an API-compatibility check: these
// signatures are hand-written from Apple's documentation and can drift. A
// green run here means "worth sending to the Mac", never "this will pass".
// When Xcode reports a signature this file gets wrong, fix it here too.
//

import Foundation

// MARK: - XCTest
//
// swift-corelibs-xctest already provides XCTestCase, the XCTAssert family,
// XCTSkip and XCTAttachment on Linux, so only what it LACKS is stubbed here.

/// swift-corelibs-xctest has no XCTAttachment; Xcode's XCTest does.
public final class XCTAttachment {
	public enum Lifetime { case keepAlways, deleteOnSuccess }
	public var name: String?
	public var lifetime: Lifetime = .deleteOnSuccess
	public init(string: String) {}
	public init(screenshot: XCUIScreenshot) {}
}

public protocol XCTActivity: AnyObject {
	func add(_ attachment: XCTAttachment)
}

public enum XCTContext {
	@discardableResult
	public static func runActivity<Result>(named name: String,
	                                       block: (XCTActivity) throws -> Result) rethrows -> Result {
		try block(StubActivity())
	}
}

public final class StubActivity: XCTActivity {
	public func add(_ attachment: XCTAttachment) {}
}

import XCTest

extension XCTestCase {
	/// Xcode's XCTestCase has this; swift-corelibs-xctest does not.
	public func add(_ attachment: XCTAttachment) {}
}

// MARK: - XCUITest

public final class XCUIScreenshot {}

public final class XCUIScreen {
	public static let main = XCUIScreen()
	public func screenshot() -> XCUIScreenshot { XCUIScreenshot() }
}

public enum XCUIKeyboardKey: String {
	case delete = "\u{8}"
	case `return` = "\n"
	public var rawValue: String { "" }
}

public class XCUIElement {
	public enum ElementType { case staticText, textField, button, cell, any }
	public enum State { case runningForeground, runningBackground, notRunning }

	public var exists: Bool { false }
	public var isHittable: Bool { false }
	public var value: Any? { nil }
	public var label: String { "" }
	public var debugDescription: String { "" }
	public var description: String { "" }

	public func tap() {}
	public func press(forDuration duration: TimeInterval) {}
	public func typeText(_ text: String) {}
	public func swipeUp() {}
	public func waitForExistence(timeout: TimeInterval) -> Bool { false }
	public func coordinate(withNormalizedOffset offset: CGVector) -> XCUICoordinate { XCUICoordinate() }

	public var identifier: String { "" }
	public var buttons: XCUIElementQuery { XCUIElementQuery() }
	public var navigationBars: XCUIElementQuery { XCUIElementQuery() }
	public var staticTexts: XCUIElementQuery { XCUIElementQuery() }
	public var textFields: XCUIElementQuery { XCUIElementQuery() }
	public var secureTextFields: XCUIElementQuery { XCUIElementQuery() }
	public var webViews: XCUIElementQuery { XCUIElementQuery() }
	public var cells: XCUIElementQuery { XCUIElementQuery() }
	public var menuItems: XCUIElementQuery { XCUIElementQuery() }
	public var keyboards: XCUIElementQuery { XCUIElementQuery() }
	public var firstMatch: XCUIElement { self }
}

public final class XCUICoordinate {
	public func tap() {}
}

public final class XCUIElementQuery {
	public var count: Int { 0 }
	public var firstMatch: XCUIElement { XCUIElement() }
	public var element: XCUIElement { XCUIElement() }
	public var allElementsBoundByIndex: [XCUIElement] { [] }
	public subscript(key: String) -> XCUIElement { XCUIElement() }
	public func matching(_ predicate: NSPredicate) -> XCUIElementQuery { self }
	public func containing(_ elementType: XCUIElement.ElementType, identifier: String?) -> XCUIElementQuery { self }
	public var buttons: XCUIElementQuery { self }
	public var navigationBars: XCUIElementQuery { self }
	public var staticTexts: XCUIElementQuery { self }
	public var textFields: XCUIElementQuery { self }
	public var secureTextFields: XCUIElementQuery { self }
	public var cells: XCUIElementQuery { self }
}

public final class XCUIApplication: XCUIElement {
	public var launchEnvironment: [String: String] = [:]
	public var launchArguments: [String] = []
	public init(bundleIdentifier: String) {}
	public func launch() {}
	public func wait(for state: XCUIElement.State, timeout: TimeInterval) -> Bool { false }
	public func screenshot() -> XCUIScreenshot { XCUIScreenshot() }
}

public struct CGVector {
	public var dx: Double
	public var dy: Double
	public init(dx: Double, dy: Double) { self.dx = dx; self.dy = dy }
}
