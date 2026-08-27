//
// AccountJourneySmokeTests.swift
// Aity Drive iOS Factory - the account journey smoke (Tier 2).
//
// LoginScreenSmokeTests proves the app starts and that the first-run screen is
// ours. This proves the app is a working DRIVE CLIENT against staging:
//
//   1. sign in as the contract user, through the app's own OIDC browser sheet,
//   2. land on the personal space and SEE A FILE that was put there before the
//      app ever launched (a spinner that stops is not a file list),
//   3. create a folder from the app, see it appear,
//   4. delete it from the app, see it go,
//   5. leave staging exactly as it was found.
//
// WHY THE BROWSER SHEET IS DRIVEN DIRECTLY. Three cheaper routes were
// investigated first and all three are dead at this Pin - the reasoning is in
// MAINTAINING.md, "Tier 2: how the OIDC login is driven". The short version:
// upstream ships no UI-test target to reuse, no branding key can pre-seed an
// account (`bookmark.prepopulation` prepopulates the local DATABASE, not the
// account), and PKCE makes callback-URL injection impossible because only the
// app knows its own code verifier. What IS available is
// `authentication.browser-session-prefers-ephermal`, a documented class
// setting that turns off the SpringBoard consent alert - the single flakiest
// element in this journey - and every class setting can be injected at launch
// through the SDK's `oc:` environment source without rebuilding anything.
//
// Credentials and endpoints arrive as TEST_RUNNER_* environment variables set
// by the fastlane lane from protected CI variables. Nothing is hardcoded here.
//

import XCTest

final class AccountJourneySmokeTests: XCTestCase {

	override func setUpWithError() throws {
		// The journey is a chain: once a step fails every later assertion is
		// noise. Teardown still runs, so staging is still cleaned up.
		continueAfterFailure = false
	}

	// MARK: - Configuration

	private func env(_ name: String, default fallback: String? = nil) throws -> String {
		if let value = ProcessInfo.processInfo.environment[name], !value.isEmpty { return value }
		if let fallback { return fallback }
		throw XCTSkip("\(name) is not set - the account journey needs the staging contract account " +
		              "(protected CI variables AITY_CONTRACT_USER / AITY_CONTRACT_PASSWORD on aity-cloud/drive)")
	}

	private var bundleIdentifier: String {
		ProcessInfo.processInfo.environment["AITY_APP_BUNDLE_ID"] ?? "tech.aity.drive.staging"
	}

	// MARK: - The journey

	func testSignInThenListCreateAndDeleteInThePersonalSpace() throws {
		let driveURL = try URL(string: env("AITY_DRIVE_URL", default: "https://drive.aity.works"))!
		let issuerURL = try URL(string: env("AITY_ISSUER", default: "https://auth.aity.works/realms/aity"))!
		let username = try env("AITY_CONTRACT_USER")
		let password = try env("AITY_CONTRACT_PASSWORD")

		let server = StagingServer(baseURL: driveURL, issuer: issuerURL, username: username, password: password)

		// --- Seed. A unique name per run, so two runs never collide and a
		// leftover from a crashed run is identifiable.
		let runID = UUID().uuidString.prefix(8).lowercased()
		let seededFile = "aity-smoke-\(runID).txt"
		let createdFolder = "aity-smoke-folder-\(runID)"

		let token = try XCTContext.runActivity(named: "Get a harness token (password grant, client `drive`)") { _ in
			try server.token()
		}
		let personal = try XCTContext.runActivity(named: "Resolve the personal space") { _ in
			try server.personalSpace(token: token)
		}
		let space = personal.webDAVURL
		_ = try XCTContext.runActivity(named: "Seed \(seededFile) into the personal space") { _ in
			try server.putFile(named: seededFile, contents: "aity drive ios smoke \(runID)\n",
			                   inSpace: space, token: token)
		}

		// Teardown runs even when an assertion below fails: staging is never
		// left littered (workspace staging-hygiene rule).
		addTeardownBlock {
			server.delete(seededFile, inSpace: space, token: token)
			server.delete(createdFolder, inSpace: space, token: token)
		}

		// --- Launch, with the consent alert turned off via the SDK's `oc:`
		// class-settings environment source.
		let app = XCUIApplication(bundleIdentifier: bundleIdentifier)
		app.launchEnvironment["oc:authentication.browser-session-prefers-ephermal"] = "bool:true"
		app.launch()

		XCTAssertTrue(app.wait(for: .runningForeground, timeout: 60), "the app did not reach the foreground")

		// --- Sign in.
		try XCTContext.runActivity(named: "Sign in through the app's OIDC browser sheet") { activity in
			advanceSetupWizard(app, activity: activity)
			try signIn(app, username: username, password: password, activity: activity)
			finishSetupWizard(app, activity: activity)
		}

		// --- The actual assertion of Tier 2: the app shows content that came
		// from the server, not just a screen that finished loading.
		XCTAssertTrue(
			waitForCell(app, named: seededFile, timeout: 180, openingSpaceNamed: personal.name),
			"'\(seededFile)' was put into the personal space over WebDAV before launch but never " +
			"appeared in the app's file list. Either the account did not open, or the list is not " +
			"the personal space.\n\n\(hierarchy(app))"
		)
		attach(app, named: "personal-space-file-list")

		// --- Create a folder from the app and watch it show up.
		XCTContext.runActivity(named: "Create the folder \(createdFolder) from the app") { _ in
			let plus = app.buttons["client.file-add"]
			XCTAssertTrue(plus.waitForExistence(timeout: 30),
			              "the add-content (+) button is missing from the personal space\n\n\(hierarchy(app))")
			plus.tap()

			let createFolder = app.buttons["Create folder"].firstMatch
			XCTAssertTrue(createFolder.waitForExistence(timeout: 20),
			              "'Create folder' is not in the + menu\n\n\(hierarchy(app))")
			createFolder.tap()

			let nameField = app.textFields["name-text-field"]
			XCTAssertTrue(nameField.waitForExistence(timeout: 20),
			              "the folder naming sheet did not appear\n\n\(hierarchy(app))")
			nameField.tap()
			// The sheet arrives prefilled with a suggested name ("New Folder"),
			// so it has to be cleared before ours is typed - otherwise the
			// folder is called "New Folderaity-smoke-...".
			clear(nameField, in: app)
			nameField.typeText(createdFolder)

			app.buttons["done-button"].tap()
		}

		XCTAssertTrue(
			waitForCell(app, named: createdFolder, timeout: 120),
			"the folder created from the app never appeared in the list\n\n\(hierarchy(app))"
		)
		attach(app, named: "after-folder-create")

		// It has to exist on the SERVER too - the list could be showing an
		// optimistic local placeholder.
		XCTAssertTrue(
			eventually(timeout: 60) { server.exists(createdFolder, inSpace: space, token: token) },
			"the app showed \(createdFolder) but the server has no such folder - the create never reached staging"
		)

		// --- Delete it from the app and watch it go.
		XCTContext.runActivity(named: "Delete \(createdFolder) from the app") { _ in
			let cell = cell(app, named: createdFolder)
			XCTAssertTrue(cell.exists, "the created folder vanished before it could be deleted")
			cell.press(forDuration: 1.2)

			let delete = app.buttons["Delete"].firstMatch
			XCTAssertTrue(delete.waitForExistence(timeout: 20),
			              "no Delete action in the item context menu\n\n\(hierarchy(app))")
			delete.tap()

			// Destructive actions confirm.
			let confirm = app.buttons["Delete"].firstMatch
			if confirm.waitForExistence(timeout: 5) { confirm.tap() }
		}

		XCTAssertTrue(
			eventually(timeout: 120) { !server.exists(createdFolder, inSpace: space, token: token) },
			"the folder deleted in the app is still on the server"
		)
		attach(app, named: "after-folder-delete")
	}

	// MARK: - Wizard

	/// The setup wizard is a sequence of steps whose exact composition depends
	/// on the Branding profile (a locked profile skips the URL step) and on
	/// what the server answers. Rather than hardcode the sequence - which turns
	/// every upstream change into a mystery failure - advance whichever known
	/// step is on screen until the browser hand-off is reached.
	private func advanceSetupWizard(_ app: XCUIApplication, activity: XCTActivity) {
		let advanceButtons = ["Start setup", "Continue", "Open login page", "Login"]
		let deadline = Date().addingTimeInterval(120)

		while Date() < deadline {
			if webUsernameField() != nil { return }

			var tapped = false
			for label in advanceButtons {
				let button = app.buttons[label]
				if button.exists && button.isHittable {
					activity.add(XCTAttachment(string: "tapped '\(label)'"))
					button.tap()
					tapped = true
					break
				}
			}
			if !tapped { _ = app.buttons.firstMatch.waitForExistence(timeout: 2) }
		}
	}

	/// After the sheet closes the composer may show a prepopulate step and then
	/// the "Account setup complete" step with a Done button.
	private func finishSetupWizard(_ app: XCUIApplication, activity: XCTActivity) {
		let deadline = Date().addingTimeInterval(180)
		while Date() < deadline {
			for label in ["Done", "Skip", "Continue"] {
				let button = app.buttons[label]
				if button.exists && button.isHittable {
					activity.add(XCTAttachment(string: "tapped '\(label)'"))
					button.tap()
				}
			}
			if app.buttons["client.file-add"].exists || app.cells.count > 0 { return }
			_ = app.buttons["client.file-add"].waitForExistence(timeout: 3)
		}
	}

	// MARK: - The browser sheet
	//
	// ASWebAuthenticationSession renders in SafariViewService, a process of its
	// own, so the fields are not necessarily in the app under test's element
	// tree. Both are searched, newest-first, rather than guessing which iOS
	// version puts them where.

	private var browserHosts: [XCUIApplication] {
		[XCUIApplication(bundleIdentifier: "com.apple.SafariViewService"),
		 XCUIApplication(bundleIdentifier: bundleIdentifier)]
	}

	private func webUsernameField() -> XCUIElement? {
		for host in browserHosts {
			let field = host.webViews.textFields.firstMatch
			if field.exists { return field }
		}
		return nil
	}

	private func webPasswordField() -> XCUIElement? {
		for host in browserHosts {
			let field = host.webViews.secureTextFields.firstMatch
			if field.exists { return field }
		}
		return nil
	}

	private func signIn(_ app: XCUIApplication, username: String, password: String, activity: XCTActivity) throws {
		// The realm's browser flow is IDENTITY-FIRST: page 1 asks for the email
		// and submits with "Continue", page 2 asks for the password and submits
		// with "Sign in". Posting both at once just redisplays page 1 - the same
		// trap the headless probe hit.
		guard let userField = waitFor({ self.webUsernameField() }, timeout: 120) else {
			XCTFail("the OIDC login page never appeared.\n\nApp:\n\(hierarchy(app))\n\n" +
			        "SafariViewService:\n\(hierarchy(XCUIApplication(bundleIdentifier: "com.apple.SafariViewService")))")
			return
		}
		trace("login page reached, typing the contract username")
		attachBrowser(named: "login-step-1-username")

		userField.tap()
		userField.typeText(username)
		activity.add(XCTAttachment(string: "typed the contract username"))

		let reachedPasswordStep = submitWebForm(
			labels: ["Continue", "Continuă", "Sign in"],
			until: { self.webPasswordField() != nil },
			timeout: 60
		)
		guard reachedPasswordStep, let passwordField = webPasswordField() else {
			attachBrowser(named: "login-step-2-missing")
			XCTFail("the password step never appeared after submitting the email.\n\n" +
			        browserHierarchies())
			return
		}
		trace("password page reached")
		attachBrowser(named: "login-step-2-password")

		passwordField.tap()
		passwordField.typeText(password)

		let left = submitWebForm(
			labels: ["Sign in", "Autentificare", "Continue"],
			until: { self.webPasswordField() == nil },
			timeout: 60
		)
		if !left {
			attachBrowser(named: "login-step-2-stuck")
			XCTFail("the password page never went away after submitting.\n\n" + browserHierarchies())
		}
	}

	/// Submits whatever login page is on screen and waits for `until`.
	///
	/// Return first, button second: the submit button of these pages sits below
	/// the fold on a phone-sized sheet, where XCUITest reports it as not
	/// hittable and refuses to tap it, while the keyboard's return key submits
	/// the form the way a person would. The button path stays as the fallback
	/// (with a swipe, in case the keyboard is not up).
	private func submitWebForm(labels: [String], until condition: () -> Bool,
	                           timeout: TimeInterval) -> Bool {
		let deadline = Date().addingTimeInterval(timeout)
		var attempt = 0
		while Date() < deadline {
			attempt += 1
			switch attempt {
			case 1:
				if let host = browserHosts.first(where: { $0.keyboards.count > 0 }) {
					trace("submitting with the keyboard return key")
					host.typeText("\n")
				}
			default:
				if tapWebButton(labels) { trace("submitted by tapping a button") }
				else if attempt == 2 {
					browserHosts.first(where: { $0.webViews.firstMatch.exists })?.swipeUp()
					trace("swiped the login page up to reach the submit button")
				}
			}

			let checkUntil = Date().addingTimeInterval(8)
			while Date() < checkUntil {
				if condition() { return true }
				usleep(500_000)
			}
		}
		return condition()
	}

	@discardableResult
	private func tapWebButton(_ labels: [String]) -> Bool {
		for host in browserHosts {
			for label in labels {
				let button = host.webViews.buttons[label].firstMatch
				if button.exists && button.isHittable { button.tap(); return true }
			}
			// Labels drift with i18n and with loading states ("Continue" becomes
			// a spinner). Fall back to any submit-looking button in the page.
			let candidate = host.webViews.buttons.allElementsBoundByIndex.first { button in
				let label = button.label.lowercased()
				return (label.contains("sign in") || label.contains("continue")
				        || label.contains("autentificare") || label.contains("continu"))
					&& button.isHittable
			}
			if let candidate { candidate.tap(); return true }
		}
		return false
	}

	private func browserHierarchies() -> String {
		browserHosts.map { host in
			"--- \(host.description.prefix(60)) ---\n\(hierarchy(host))"
		}.joined(separator: "\n\n")
	}

	/// Empty a text field. The clear button is the reliable route when the
	/// field has one; select-all is the fallback.
	private func clear(_ field: XCUIElement, in app: XCUIApplication) {
		let clearButton = field.buttons["Clear text"]
		if clearButton.exists && clearButton.isHittable {
			clearButton.tap()
			return
		}
		field.press(forDuration: 1.2)
		let selectAll = app.menuItems["Select All"]
		if selectAll.waitForExistence(timeout: 3) {
			selectAll.tap()
			return
		}
		let existing = (field.value as? String) ?? ""
		field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: existing.count))
	}

	// MARK: - Small waiting helpers
	//
	// waitForExistence covers one element; these cover "some condition about
	// the app becomes true", which is most of what this journey waits on.

	private func waitFor<T>(_ probe: () -> T?, timeout: TimeInterval) -> T? {
		let deadline = Date().addingTimeInterval(timeout)
		while Date() < deadline {
			if let value = probe() { return value }
			usleep(500_000)
		}
		return probe()
	}

	private func eventually(timeout: TimeInterval, _ condition: () -> Bool) -> Bool {
		let deadline = Date().addingTimeInterval(timeout)
		while Date() < deadline {
			if condition() { return true }
			usleep(1_000_000)
		}
		return condition()
	}

	private func cell(_ app: XCUIApplication, named name: String) -> XCUIElement {
		app.cells.containing(.staticText, identifier: name).firstMatch
	}

	private func waitForCell(_ app: XCUIApplication, named name: String, timeout: TimeInterval) -> Bool {
		eventually(timeout: timeout) {
			app.staticTexts[name].exists || self.cell(app, named: name).exists
		}
	}

	/// Same, but opens the personal space first if the app landed on the
	/// account/spaces overview instead of inside it. The space's name is the
	/// user's DISPLAY NAME on oCIS, not the word "Personal", so it is read from
	/// `/graph/v1.0/me/drives` rather than guessed.
	private func waitForCell(_ app: XCUIApplication, named name: String, timeout: TimeInterval,
	                         openingSpaceNamed spaceName: String) -> Bool {
		let deadline = Date().addingTimeInterval(timeout)
		var opened = false
		var lastTrace = Date.distantPast
		while Date() < deadline {
			if app.staticTexts[name].exists || cell(app, named: name).exists { return true }
			if !opened {
				let entry = app.staticTexts[spaceName].firstMatch
				if entry.exists && entry.isHittable {
					trace("opening the personal space '\(spaceName)' from the overview")
					entry.tap()
					opened = true
				}
			}
			// Without this, a run that never finds the file spends three
			// minutes printing "Checking existence of ..." and says nothing
			// about what WAS on screen.
			if Date().timeIntervalSince(lastTrace) > 20 {
				trace("still waiting for '\(name)'; \(visibleLabels(app))")
				lastTrace = Date()
			}
			usleep(1_000_000)
		}
		return app.staticTexts[name].exists || cell(app, named: name).exists
	}

	// MARK: - Diagnostics
	//
	// A failing UI test that only says "element not found" costs a whole CI
	// round trip on shared Mac hardware. Every failure message carries the
	// element tree, and each phase attaches a screenshot.

	/// print() lands in the xcodebuild transcript, which is the only diagnostic
	/// that can be read without a Mac (attachments live inside the .xcresult).
	private func trace(_ message: String) {
		print("[aity-smoke] \(message)")
	}

	/// XCUIApplication.debugDescription prints only the query chain once the
	/// app is not attached, which is exactly when a failure needs it most. The
	/// labels of what is on screen are always available and are what a human
	/// reads anyway.
	private func visibleLabels(_ app: XCUIApplication) -> [String] {
		var labels: [String] = []
		for query in [app.staticTexts, app.buttons, app.cells] {
			labels += query.allElementsBoundByIndex.prefix(60).map { $0.label }
		}
		return Array(Set(labels.filter { !$0.isEmpty })).sorted()
	}

	private func hierarchy(_ app: XCUIApplication) -> String {
		"visible labels: \(visibleLabels(app))\n\n" + String(app.debugDescription.prefix(8_000))
	}

	private func attach(_ app: XCUIApplication, named name: String) {
		let screenshot = XCTAttachment(screenshot: app.screenshot())
		screenshot.name = name
		screenshot.lifetime = .keepAlways
		add(screenshot)

		let tree = XCTAttachment(string: hierarchy(app))
		tree.name = "\(name).hierarchy.txt"
		tree.lifetime = .keepAlways
		add(tree)
	}

	private func attachBrowser(named name: String) {
		let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
		screenshot.name = name
		screenshot.lifetime = .keepAlways
		add(screenshot)
	}
}
