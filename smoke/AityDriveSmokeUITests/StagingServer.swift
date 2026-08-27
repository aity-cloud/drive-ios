//
// StagingServer.swift
// Aity Drive iOS Factory - the smoke's server-side helper.
//
// The account-journey test needs two things the app cannot give it: a file
// that is already in the account before the app ever logs in (so "the list
// shows my files" is an assertion about real content, not about a spinner
// stopping), and a way to clean up if the UI half of the test dies mid-run.
//
// Both are done here with the SAME password grant Tier 1 uses
// (meta/contract/drive_contract.py, client `drive`) - deliberately NOT the
// `drive-ios` client, which is the one the APP must exercise through its own
// browser sheet. Keeping the harness on a different client means the test can
// never accidentally paper over a broken `drive-ios` registration.
//
// Everything is synchronous on purpose: XCTest is synchronous, and a smoke
// that needs async plumbing to read one file listing is a smoke nobody will
// maintain.
//

import Foundation

struct StagingServer {
	let baseURL: URL
	let issuer: URL
	let username: String
	let password: String

	enum ServerError: Error, CustomStringConvertible {
		case transport(String)
		case http(Int, String)
		case malformed(String)

		var description: String {
			switch self {
			case .transport(let detail): return "transport failure: \(detail)"
			case .http(let code, let detail): return "HTTP \(code): \(detail)"
			case .malformed(let detail): return "unexpected response: \(detail)"
			}
		}
	}

	// MARK: - Plumbing

	private func send(_ request: URLRequest) throws -> (Int, Data) {
		var result: Result<(Int, Data), Error>?
		let done = DispatchSemaphore(value: 0)

		URLSession.shared.dataTask(with: request) { data, response, error in
			if let error {
				result = .failure(ServerError.transport(error.localizedDescription))
			} else if let http = response as? HTTPURLResponse {
				result = .success((http.statusCode, data ?? Data()))
			} else {
				result = .failure(ServerError.malformed("no HTTP response"))
			}
			done.signal()
		}.resume()

		guard done.wait(timeout: .now() + 60) == .success else {
			throw ServerError.transport("timed out after 60s: \(request.url?.absoluteString ?? "?")")
		}
		return try result!.get()
	}

	private func form(_ url: URL, _ fields: [String: String]) throws -> (Int, Data) {
		var request = URLRequest(url: url)
		request.httpMethod = "POST"
		request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
		request.httpBody = fields
			.map { "\($0.key)=\(Self.escape($0.value))" }
			.joined(separator: "&")
			.data(using: .utf8)
		return try send(request)
	}

	private static func escape(_ value: String) -> String {
		var allowed = CharacterSet.alphanumerics
		allowed.insert(charactersIn: "-._~")
		return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
	}

	private func authorized(_ method: String, _ url: URL, token: String, body: Data? = nil,
	                        headers: [String: String] = [:]) throws -> (Int, Data) {
		var request = URLRequest(url: url)
		request.httpMethod = method
		request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
		request.setValue("aity-drive-ios-smoke/1.0", forHTTPHeaderField: "User-Agent")
		for (key, value) in headers { request.setValue(value, forHTTPHeaderField: key) }
		request.httpBody = body
		return try send(request)
	}

	// MARK: - The three things the test needs

	/// Access token for the harness. Password grant on the `drive` client, as
	/// Tier 1 does; the realm allows it for that client only.
	func token() throws -> String {
		let (status, data) = try form(issuer.appendingPathComponent("protocol/openid-connect/token"), [
			"client_id": "drive",
			"grant_type": "password",
			"scope": "openid profile email",
			"username": username,
			"password": password,
		])
		guard status == 200 else {
			throw ServerError.http(status, String(data: data, encoding: .utf8) ?? "")
		}
		guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
		      let token = json["access_token"] as? String else {
			throw ServerError.malformed("no access_token in the token response")
		}
		return token
	}

	/// WebDAV URL of the personal space, as the SERVER advertises it. A client
	/// follows what it is given, so the harness does too.
	func personalSpaceWebDAVURL(token: String) throws -> URL {
		let (status, data) = try authorized("GET", baseURL.appendingPathComponent("graph/v1.0/me/drives"), token: token)
		guard status == 200 else {
			throw ServerError.http(status, String(data: data, encoding: .utf8) ?? "")
		}
		guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
		      let drives = json["value"] as? [[String: Any]] else {
			throw ServerError.malformed("no drive list")
		}
		guard let personal = drives.first(where: { ($0["driveType"] as? String) == "personal" }),
		      let root = personal["root"] as? [String: Any],
		      let webDAV = root["webDavUrl"] as? String, let url = URL(string: webDAV) else {
			throw ServerError.malformed("no personal space with a webDavUrl in \(drives.count) drive(s)")
		}
		return url
	}

	@discardableResult
	func putFile(named name: String, contents: String, inSpace space: URL, token: String) throws -> Int {
		let (status, data) = try authorized("PUT", space.appendingPathComponent(name), token: token,
		                                    body: contents.data(using: .utf8),
		                                    headers: ["Content-Type": "text/plain"])
		guard status == 201 || status == 204 else {
			throw ServerError.http(status, String(data: data, encoding: .utf8) ?? "")
		}
		return status
	}

	/// Best effort: teardown must never turn a red test into a red *and*
	/// littered staging, but it must also never mask the original failure.
	func delete(_ name: String, inSpace space: URL, token: String) {
		_ = try? authorized("DELETE", space.appendingPathComponent(name), token: token)
	}

	func exists(_ name: String, inSpace space: URL, token: String) -> Bool {
		guard let (status, _) = try? authorized("PROPFIND", space.appendingPathComponent(name), token: token,
		                                        headers: ["Depth": "0", "Content-Type": "application/xml"]) else {
			return false
		}
		return status == 207 || status == 200
	}
}
