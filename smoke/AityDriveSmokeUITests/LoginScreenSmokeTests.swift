//
// LoginScreenSmokeTests.swift
// Aity Drive iOS Factory - login-screen smoke.
//
// Launches the Environment build that build_simulator_smoke installed on
// the simulator and asserts the branded, locked-profile first-run screen:
//
//   - the app starts and settles (no launch crash),
//   - the bookmark setup wizard greets with "Welcome to <app name>"
//     (BookmarkSetupStepIntroViewController of the Pin) and offers
//     "Start setup",
//   - no server URL entry is reachable on the first screen - the profile
//     is locked (branding.profile-allow-url-configuration = false).
//   - on a Romanian phone the same screen is Romanian: the Factory's
//     l10n/ro reached the String Catalogs and iOS selects it.
//
// The bundle id and app name arrive via TEST_RUNNER_* environment
// variables set by the fastlane lane; the defaults match the staging
// Environment, which is what the smoke stage runs against.
//

import XCTest

final class LoginScreenSmokeTests: XCTestCase {

	private var bundleIdentifier: String {
		ProcessInfo.processInfo.environment["AITY_APP_BUNDLE_ID"] ?? "tech.aity.drive.staging"
	}

	private var appName: String {
		ProcessInfo.processInfo.environment["AITY_APP_NAME"] ?? "Aity Drive (staging)"
	}

	func testLoginScreenIsBrandedAndLocked() {
		let app = XCUIApplication(bundleIdentifier: bundleIdentifier)
		app.launch()

		let welcome = app.staticTexts["Welcome to \(appName)"]
		XCTAssertTrue(
			welcome.waitForExistence(timeout: 60),
			"Branded welcome title 'Welcome to \(appName)' did not appear - " +
			"branding.app-name or the bookmark setup flow changed"
		)

		let startSetup = app.buttons["Start setup"]
		XCTAssertTrue(
			startSetup.waitForExistence(timeout: 10),
			"'Start setup' button missing from the setup intro screen"
		)

		XCTAssertEqual(
			app.textFields.count, 0,
			"The locked-profile intro screen must not offer any text entry " +
			"(branding.profile-allow-url-configuration = false)"
		)
	}

	func testLoginScreenIsRomanianOnARomanianPhone() {
		let app = XCUIApplication(bundleIdentifier: bundleIdentifier)
		app.launchArguments += ["-AppleLanguages", "(ro)", "-AppleLocale", "ro_RO"]
		app.launch()

		let welcome = app.staticTexts["Bun venit în \(appName)"]
		XCTAssertTrue(
			welcome.waitForExistence(timeout: 60),
			"'Bun venit în \(appName)' did not appear on a Romanian phone - the ro localization " +
			"is missing from the bundle or iOS did not select it"
		)
		XCTAssertTrue(app.buttons["Începe configurarea"].waitForExistence(timeout: 10),
		              "'Începe configurarea' missing from the Romanian setup intro screen")

		let screenshot = XCTAttachment(screenshot: app.screenshot())
		screenshot.name = "login-screen-ro"
		screenshot.lifetime = .keepAlways
		add(screenshot)
	}
}
