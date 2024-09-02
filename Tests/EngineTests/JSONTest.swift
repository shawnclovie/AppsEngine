//
//  JSONTest.swift
//  
//
//  Created by Shawn Clovie on 2023/4/15.
//

import XCTVapor
@testable import AppsEngine

final class JSONTest: XCTestCase {
	var measureOptions: XCTMeasureOptions {
		let opt = XCTMeasureOptions()
		opt.iterationCount = 20
		return opt
	}

	static let jsonObject: [String: JSON] = [
		"foo": [
			"name": ["foo1": "bar"],
			"nums": ["a", nil, "b", 4],
		],
		"null": nil,
		"bool": true,
		"int8": 23,
		"int64": 9223372036854775807,
		"float": 1.1,
		"double": 3.141592642,
		"array": [1, 2, false, 235990, 234, "lk23", nil],
		"arrayEmpty": [],
		"objEmpty": [:],
		"url": "https://www.google.com/?q=搜索word&foo=bar",
		"st\\ri\"ng": "tes&%\\ { 👨‍👨‍👧‍👦cancelled👩‍👩‍👦‍👦tcancelled   cancelled中国  的fql23",
	]

	func testJSON() throws {
		var obj = JSON.object(Self.jsonObject)
		XCTAssertEqual("bar", obj.valueForKeys(["foo", "name", "foo1"]).stringValue)
		XCTAssertEqual(1.1, obj["float"].valueAsDouble)
		XCTAssertEqual(JSON.null, JSON(from: nil))
		XCTAssertEqual(JSON.bool(false), JSON(from: false))
		XCTAssertEqual(JSON.number(1.1), JSON(from: 1.1))
		let abc = "abc"
		XCTAssertEqual(JSON.string(abc), JSON(from: abc))
		XCTAssertEqual(JSON.string("a"), JSON(from: abc.dropLast(2)))
		XCTAssertEqual(JSON.array([JSON.string(abc)]), JSON(from: [abc]))
		XCTAssertEqual(JSON.object([abc: JSON.string(abc)]), JSON(from: [abc: abc]))
		XCTAssertEqual(JSON.null, JSON(from: Errors.not_found))

		obj["int8"] = .init(from: 24)
		XCTAssertEqual(24, obj["int8"].valueAsInt64)
		obj.setValues([
			"int8": .init(from: 25),
			"bool": .bool(false),
		])
		XCTAssertEqual(25, obj["int8"].valueAsInt64)
		XCTAssertEqual(false, obj["bool"].boolValue)

		var arr = JSON.array([])
		arr.append(.null)
		XCTAssertEqual(1, arr.arrayValue!.count)
		arr.append(contentsOf: [.null, .null])
		XCTAssertEqual(3, arr.arrayValue!.count)
		arr.insert(.bool(true), at: 1)
		XCTAssertEqual(4, arr.arrayValue!.count)
	}

	func testJSONNumber() {
		for (s, v) in [
			"1.0211": 1.0211,
			"1.1": NSNumber(1.1),
			"2.3": Decimal(1.1) + Decimal(1.2),
			"0.0000000000031415926": Decimal(string: "3.1415926e-12")!,
			"0.000000000000000000031415926": Decimal(string: "3.1415926e-20")!,
		] {
			let num = JSON(from: v)
			XCTAssertEqual(s, num.description)
		}
		let num: UInt8 = 1
		XCTAssertEqual(JSON.number(num), JSON(from: num))
		XCTAssertEqual(JSON.number(UInt64(1)), JSON(from: 1))
		XCTAssertEqual(JSON.number(UInt64(Int64.max)), JSON(from: Int64.max))
		XCTAssertEqual("0.0000314", JSON.number(Double("3.14e-5")!).description)
		XCTAssertEqual("-0.0000314", JSON.number(Double("-3.14e-5")!).description)
		XCTAssertEqual("314000", JSON.number(Double("3.14e5")!).description)
		XCTAssertEqual("-314000", JSON.number(Double("-3.14e5")!).description)
	}

	func testJSONCodable() throws {
		let obj = JSON.object(Self.jsonObject)
		let encoder = JSON.Encoder(options: [.sortedKeys])
		let s = encoder.encode(obj)
		print(s)
		do {
			let encoder = JSONEncoder()
			encoder.outputFormatting = [.sortedKeys]
			let s1 = String(decoding: try encoder.encode(obj), as: UTF8.self)
			print(s1)
		}
		let value = try JSON.Decoder().decode(s.data(using: .utf8)!)
		XCTAssertEqual(s, encoder.encode(value))
	}

	func testNumberCodable() throws {
		struct A: Codable {
			var num: JSON
		}
		for text in [
			"{\"num\":1.7}",
			"{\"num\":\"1.7\"}",
			"{\"num\":\"\"}",
		] {
			print("decoding", text)
			let a = try JSONDecoder().decode(A.self, from: Data(text.utf8))
			print(a.num)
			let encoded = try JSONEncoder().encode(a)
			print(String(decoding: encoded, as: UTF8.self))
		}
		let num1 = try JSONDecoder().decode(JSON.self, from: Data("1.5".utf8))
		let num1c = JSON.number(num1.valueAsDouble!)
		XCTAssertEqual(num1, num1c)
		XCTAssertEqual(1, num1.valueAsInt64)
	}

	func testJSONMetricString() throws {
		measure(options: measureOptions) {
			let _ = JSON.Encoder(options: []).encode(JSON.object(Self.jsonObject))
		}
	}

	func testLogMeasure() {
		let log = Log(level: .debug, "abc", [
			.init("str", "ocume\\nts/wo\"rks/company/bsto\"neinfo/microservice/swift_base_server/Tests/EngineTests/UtilityTests.swift"),
			.init("data", Data([0x56, 0x02])),
			.init("arr", JSON.array([1, 2])),
			.init("obj", JSON.object(["key": .object(["foo": .string("bar")])])),
			.error(WrapError(.internal, AnyError("some"))),
		], timezone: nil)
		print(String(decoding: log.encodeAsData(), as: UTF8.self))
		measure(options: measureOptions) {
			for _ in 0..<1000 {
				_ = log.encodeAsBuffer()
			}
		}
	}
}
