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
}
