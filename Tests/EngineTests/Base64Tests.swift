//
//  Base64Tests.swift
//  
//
//  Created by Shawn Clovie on 2023/4/3.
//

import Foundation
import XCTest
@testable import AppsEngine

final class Base64Tests: XCTestCase {

	func testOK() throws {
		struct Pair {
			let decoded: Data
			let encoded: String
			let encodedURLSafe: String
			let encodedURLSafeNoPad: String

			init(_ decoded: String, _ encoded: String) {
				self.init(Data(decoded.utf8), encoded)
			}

			init(_ decoded: Data, _ encoded: String) {
				self.decoded = decoded//String(decoding: decoded, as: Unicode.ASCII.self)
				self.encoded = encoded
				encodedURLSafe = encoded
					.replacingOccurrences(of: "+", with: "-")
					.replacingOccurrences(of: "/", with: "_")
				encodedURLSafeNoPad = encodedURLSafe
					.trimmingCharacters(in: .init(charactersIn: "="))
			}
		}

		let pairs: [Pair] = [
			// RFC 3548 examples
			.init(Data([0x14, 0xfb, 0x9c, 0x03, 0xd9, 0x7e]), "FPucA9l+"),
			.init(Data([0x14, 0xfb, 0x9c, 0x03, 0xd9]), "FPucA9k="),
			.init(Data([0x14, 0xfb, 0x9c, 0x03]), "FPucAw=="),

			// RFC 4648 examples
			.init("", ""),
			.init("f", "Zg=="),
			.init("fo", "Zm8="),
			.init("foo", "Zm9v"),
			.init("foob", "Zm9vYg=="),
			.init("fooba", "Zm9vYmE="),
			.init("foobar", "Zm9vYmFy"),

			// Wikipedia examples
			.init("sure.", "c3VyZS4="),
			.init("sure", "c3VyZQ=="),
			.init("sur", "c3Vy"),
			.init("su", "c3U="),
			.init("leasure.", "bGVhc3VyZS4="),
			.init("easure.", "ZWFzdXJlLg=="),
			.init("asure.", "YXN1cmUu"),
			.init("sure.", "c3VyZS4="),
		]
		for pair in pairs {
			do {
				let encoding = Base64Encoding.urlSafeNoPad
				let encoded = encoding.encode(pair.decoded)
				XCTAssertEqual(pair.encodedURLSafeNoPad, String(decoding: encoded, as: UTF8.self))
				let decoded = encoding.decode(encoded)
				XCTAssertEqual(pair.decoded, decoded)
			}
			do {
				let encoding = Base64Encoding.standard
				let encoded = encoding.encode(pair.decoded)
				XCTAssertEqual(pair.encoded, String(decoding: encoded, as: UTF8.self))
				let decoded = encoding.decode(encoded)
				XCTAssertEqual(pair.decoded, decoded)
			}
		}
	}

	let base64StandardEncoded = """
CP/EAT8AAAEF
AQEBAQEBAAAAAAAAAAMAAQIEBQYHCAkKCwEAAQUBAQEBAQEAAAAAAAAAAQACAwQFBgcICQoLEAAB
BAEDAgQCBQcGCAUDDDMBAAIRAwQhEjEFQVFhEyJxgTIGFJGhsUIjJBVSwWIzNHKC0UMHJZJT8OHx
Y3M1FqKygyZEk1RkRcKjdDYX0lXiZfKzhMPTdePzRieUpIW0lcTU5PSltcXV5fVWZnaGlqa2xtbm
9jdHV2d3h5ent8fX5/cRAAICAQIEBAMEBQYHBwYFNQEAAhEDITESBEFRYXEiEwUygZEUobFCI8FS
0fAzJGLhcoKSQ1MVY3M08SUGFqKygwcmNcLSRJNUoxdkRVU2dGXi8rOEw9N14/NGlKSFtJXE1OT0
pbXF1eX1VmZ2hpamtsbW5vYnN0dXZ3eHl6e3x//aAAwDAQACEQMRAD8A9VSSSSUpJJJJSkkkJ+Tj
1kiy1jCJJDnAcCTykpKkuQ6p/jN6FgmxlNduXawwAzaGH+V6jn/R/wCt71zdn+N/qL3kVYFNYB4N
ji6PDVjWpKp9TSXnvTf8bFNjg3qOEa2n6VlLpj/rT/pf567DpX1i6L1hs9Py67X8mqdtg/rUWbbf
+gkp0kkkklKSSSSUpJJJJT//0PVUkkklKVLq3WMDpGI7KzrNjADtYNXvI/Mqr/Pd/q9W3vaxjnvM
NaCXE9gNSvGPrf8AWS3qmba5jjsJhoB0DAf0NDf6sevf+/lf8Hj0JJATfWT6/dV6oXU1uOLQeKKn
EQP+Hubtfe/+R7Mf/g7f5xcocp++Z11JMCJPgFBxOg7/AOuqDx8I/ikpkXkmSdU8mJIJA/O8EMAy
j+mSARB/17pKVXYWHXjsj7yIex0PadzXMO1zT5KHoNA3HT8ietoGhgjsfA+CSnvvqh/jJtqsrwOv
2b6NGNzXfTYexzJ+nU7/ALkf4P8Awv6P9KvTQQ4AgyDqCF85Pho3CTB7eHwXoH+LT65uZbX9X+o2
bqbPb06551Y4
"""

	func testPerformance() {
		let enc1line = base64StandardEncoded.replacingOccurrences(of: "\n", with: "")
		measure {
			_ = Base64Encoding.standard.decode(enc1line)!
		}
//		let data = Base64Encoding.standard.decode(enc1line)!
//		measure {
//			_ = Base64Encoding.urlSafeNoPad.encode(data)
//		}
//		let b64urlSafe = Base64Encoding.urlSafeNoPad.encode(data)
//		measure {
//			_ = Base64Encoding.urlSafeNoPad.decode(b64urlSafe)
//		}
	}
}
