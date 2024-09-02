import XCTest
@testable import AppsEngine

final class TypesTest: XCTestCase {
	func testAnyToTypes() {
		XCTAssertEqual(0, anyToInt64(0))
		XCTAssertEqual(3, anyToInt64(3.14))
		XCTAssertEqual(3, anyToInt64((Double("3.14")! as NSNumber).decimalValue))
		XCTAssertEqual(nil, anyToInt64(UInt64.max))
		XCTAssertEqual(nil, anyToInt64(Double(UInt64.max)))
		XCTAssertEqual(nil, anyToInt64(Double(UInt64.max) * -1))
		XCTAssertEqual(nil, anyToInt64(Float(UInt64.max)))
		XCTAssertEqual(nil, anyToInt64(NSNumber(value: UInt64.max)))
		XCTAssertEqual(nil, anyToInt64(NSNumber(value: UInt64.max).decimalValue))
		XCTAssertEqual(nil, anyToInt64("\(UInt64.max)"))
		XCTAssertEqual(Int64.max, anyToInt64("\(Int64.max)"))

		XCTAssertEqual(3, anyToUInt64(3.14))
		XCTAssertEqual(3, anyToUInt64((Double("3.14")! as NSNumber).decimalValue))
		XCTAssertEqual(nil, anyToUInt64(-3.14))
		XCTAssertEqual(nil, anyToUInt64(-3))
		XCTAssertEqual(0, anyToUInt64(0))
		XCTAssertEqual(UInt64.max, anyToUInt64(UInt64.max))
		XCTAssertEqual(nil, anyToUInt64(Double(UInt64.max)))
		XCTAssertEqual(nil, anyToUInt64(Float(UInt64.max)))
		XCTAssertEqual(UInt64.max, anyToUInt64(NSNumber(value: UInt64.max)))
		XCTAssertEqual(UInt64.max, anyToUInt64(NSNumber(value: UInt64.max).decimalValue))
		XCTAssertEqual(UInt64.max, anyToUInt64("\(UInt64.max)"))
		XCTAssertEqual(nil, anyToUInt64("-\(UInt64.max)"))
	}
}

final class SnowflakeTests: XCTestCase {
	
	override func setUp() {
		super.setUp()
		let formatter = DateFormatter()
		formatter.dateFormat = "yyyy-MM-dd ZZZ"
		print("epoch of custom date:", Snowflake.Node.flakeTimestamp(Time(formatter.date(from: "2018-01-01 UTC")!)))
		print("epoch of now:", Snowflake.Node.flakeTimestamp(Time(Date())))
	}
	
    func testGenerate() {
		let count = 1010
		let node = Snowflake.Node(node: 1)
		var ids: Set<Snowflake.ID> = []
		for _ in 0..<count {
			ids.insert(node.generate())
		}
		XCTAssert(ids.count == count)
		
		let id = Snowflake.ID(324932740761784320)
		let b2 = "10010000010011001001001101100101101000000000001000000000000"
		let b32 = "jyurucsoyryy"
		let b36 = "2gvf1kdqtc00"
		let b58 = "KKhC7rdSPA"
		let b64 = "MzI0OTMyNzQwNzYxNzg0MzIw"
		XCTAssertEqual(id.base2, b2)
		XCTAssertEqual(id.base32, b32)
		XCTAssertEqual(id.base36, b36)
		XCTAssertEqual(id.base58, b58)
		XCTAssertEqual(id.base64, b64)
		XCTAssertEqual(id, Snowflake.ID(base2: b2))
		XCTAssertEqual(id, Snowflake.ID(base36: b36))
		XCTAssertEqual(id, Snowflake.ID(base64: b64))
    }
	
	func testGenerateBenchmark() {
		let opt = XCTMeasureOptions()
		opt.iterationCount = 10000
		let node = Snowflake.Node(node: 1)
		var ids: [Snowflake.ID] = []
		self.measure(options: opt) {
			let id = node.generate()
			ids.append(id)
		}
		print(ids)
	}
}
