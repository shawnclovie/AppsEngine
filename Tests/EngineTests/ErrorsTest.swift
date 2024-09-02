//
//  ErrorsTest.swift
//
//
//  Created by Shawn Clovie on 2024/8/3.
//

import Foundation
@testable import AppsEngine
import XCTVapor

final class ErrorsTest: XCTestCase {
	func testWrap() {
		let base = Errors.internal
		var err = WrapError(base, AnyError("a error description for a"))
			.wrap("cancelled for test")
			.wrap("3rd error")
		XCTAssertEqual(base, err.base)
		err = err.wrap(Errors.forbidden)
		XCTAssertEqual(Errors.forbidden, err.base)
		XCTAssertTrue(err.contains(oneOf: base, .internal))
		XCTAssertFalse(err.contains(oneOf: .database, .invalid_app_config))
		print(err.description)
		print(err.description(withCaller: true, useReflect: true))
	}

	func testResponseError() {
		let err = WrapError(.database, WrapError(.app_not_found, [
			"app_id": "z",
		]), JSONTest.jsonObject)
		print(HTTPResponse.error(headers: .init([("Accept", "gzip")]), err).bytes.string)
		print(HTTPResponse.error(headers: .init([
			("Accept", "gzip"),
			(HTTP.Header.content_type, HTTPMediaType.plainText.description),
		]), err).bytes.string)
	}

	func testWithOrWithoutCode() {
		struct SomeError: Error, CustomStringConvertible, CustomDebugStringConvertible {
			let name: String
			let code: String

			var description: String { name }
			var debugDescription: String { "\(name) code \(code)" }
		}
		let wrapped = SomeError(name: "Jack", code: "No.1")
		let err = Errors.internal.convertOrWrap(AnyError("a", debug: "debug", wrap: wrapped))
		// without `code`
		print(err.description)
		XCTAssertFalse(err.description.contains(wrapped.code))
		XCTAssertFalse(HTTPResponse.error(err).bytes.string.contains(wrapped.code))
		// with `code`
		print(err.debugDescription)
		XCTAssertTrue(err.debugDescription.contains(wrapped.code))
		AppsEngine.Logger(label: "A", outputers: [LogClosureOutputer(level: .debug, closure: { log in
			let text = log.encodeAsBuffer().string
			XCTAssertTrue(text.contains(wrapped.code))
			print(text)
		})]).log(.error, "MSG", .error(err))
	}
}
