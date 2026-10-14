//
// TOTP.swift
// Aity Drive iOS Factory - the contract account's Authenticator App code.
//
// RFC 6238 (HMAC-SHA1, 6 digits, 30 s step) from the base32 seed an
// authenticator app shows, the same as meta/contract/totp.py.
//

import Foundation
#if canImport(CommonCrypto)
import CommonCrypto
#endif

enum TOTP {
	static let step: TimeInterval = 30

	nonisolated(unsafe) private static var lastStep: Int64 = -1

	/// A code from a step this run has not used yet: Keycloak accepts each code
	/// once per user, and the harness grant and the app's sign-in are two uses.
	static func freshCode(secret: String) -> String? {
		if Int64(Date().timeIntervalSince1970 / step) <= lastStep {
			Thread.sleep(forTimeInterval: step - Date().timeIntervalSince1970.truncatingRemainder(dividingBy: step) + 1)
		}
		let now = Date()
		lastStep = Int64(now.timeIntervalSince1970 / step)
		return code(secret: secret, at: now)
	}

	static func code(secret: String, at date: Date) -> String? {
		guard let key = base32Decode(secret) else { return nil }
		let counter = UInt64(date.timeIntervalSince1970 / step)
		let mac = hmacSHA1(key: key, message: withUnsafeBytes(of: counter.bigEndian) { Array($0) })
		let offset = Int(mac[19] & 0x0f)
		let value = mac[offset..<offset + 4].reduce(UInt32(0)) { $0 << 8 | UInt32($1) } & 0x7fff_ffff
		let digits = String(value % 1_000_000)
		return String(repeating: "0", count: 6 - digits.count) + digits
	}

	private static func base32Decode(_ text: String) -> [UInt8]? {
		let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567")
		var bits = 0, buffer = 0
		var bytes: [UInt8] = []
		for character in text.uppercased() where !character.isWhitespace && character != "=" {
			guard let index = alphabet.firstIndex(of: character) else { return nil }
			buffer = (buffer << 5 | index) & 0xffff
			bits += 5
			if bits >= 8 {
				bits -= 8
				bytes.append(UInt8(truncatingIfNeeded: buffer >> bits))
			}
		}
		return bytes.isEmpty ? nil : bytes
	}

	private static func hmacSHA1(key: [UInt8], message: [UInt8]) -> [UInt8] {
		#if canImport(CommonCrypto)
		var mac = [UInt8](repeating: 0, count: Int(CC_SHA1_DIGEST_LENGTH))
		CCHmac(CCHmacAlgorithm(kCCHmacAlgSHA1), key, key.count, message, message.count, &mac)
		return mac
		#else
		var block = key.count > 64 ? sha1(key) : key
		block += [UInt8](repeating: 0, count: 64 - block.count)
		return sha1(block.map { $0 ^ 0x5c } + sha1(block.map { $0 ^ 0x36 } + message))
		#endif
	}

	#if !canImport(CommonCrypto)
	// Linux has no CommonCrypto; this is what scripts/check-smoke-swift.sh compiles.
	private static func sha1(_ message: [UInt8]) -> [UInt8] {
		var h: [UInt32] = [0x6745_2301, 0xEFCD_AB89, 0x98BA_DCFE, 0x1032_5476, 0xC3D2_E1F0]
		var data = message + [0x80]
		data += [UInt8](repeating: 0, count: (120 - data.count % 64) % 64)
		data += withUnsafeBytes(of: UInt64(message.count * 8).bigEndian) { Array($0) }
		for chunk in stride(from: 0, to: data.count, by: 64) {
			var w = (0..<16).map { i in
				data[chunk + 4 * i..<chunk + 4 * i + 4].reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
			}
			for i in 16..<80 {
				let x = w[i - 3] ^ w[i - 8] ^ w[i - 14] ^ w[i - 16]
				w.append(x << 1 | x >> 31)
			}
			var (a, b, c, d, e) = (h[0], h[1], h[2], h[3], h[4])
			for i in 0..<80 {
				let f: UInt32, k: UInt32
				if i < 20 { f = (b & c) | (~b & d); k = 0x5A82_7999 }
				else if i < 40 { f = b ^ c ^ d; k = 0x6ED9_EBA1 }
				else if i < 60 { f = (b & c) | (b & d) | (c & d); k = 0x8F1B_BCDC }
				else { f = b ^ c ^ d; k = 0xCA62_C1D6 }
				let t = (a << 5 | a >> 27) &+ f &+ e &+ k &+ w[i]
				(e, d, c, b, a) = (d, c, b << 30 | b >> 2, a, t)
			}
			h = [h[0] &+ a, h[1] &+ b, h[2] &+ c, h[3] &+ d, h[4] &+ e]
		}
		return h.flatMap { word in withUnsafeBytes(of: word.bigEndian) { Array($0) } }
	}
	#endif
}
