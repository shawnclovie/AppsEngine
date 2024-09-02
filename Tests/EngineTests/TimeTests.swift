import XCTest
@testable import AppsEngine

final class TimeTests: XCTestCase {
    func testParseTimeDuration() throws {
		struct Item {
			let source: String
			let defaultUnit: String?
			let match: TimeDuration
			
			init(_ src: String, defaultUnit: String? = nil, match: TimeDuration, export: String? = nil) {
				source = src
				self.defaultUnit = defaultUnit
				self.match = match
			}
		}
		let items: [Item] = [
			.init("1d2h3m0s5ms4us", match: .hours(26) + .minutes(3) + .milliseconds(5) + .microseconds(4)),
			.init("+1d", match: .hours(24)),
			.init("-1d", match: .hours(-24)),
			.init("", match: .zero),
			.init("0", match: .zero),
			.init("300", match: .seconds(300)),
			.init("300", defaultUnit: "ms", match: .milliseconds(300)),
			.init("1.5h", match: .hours(1) + .minutes(30)),
			.init(".5h", match: .minutes(30)),
			.init("-.5h", match: .minutes(-30)),
			.init("1d1d", match: .hours(48)),
		]
		for (i, item) in items.enumerated() {
			let dur = TimeDuration.parse(item.source, defaultUnit: item.defaultUnit ?? TimeDuration.defaultParseUnit)
			XCTAssertEqual(dur, item.match, "[\(i)] \(item.source)")
			let reparsed = TimeDuration.parse(dur.description)
			XCTAssertEqual(reparsed, dur, "[\(i)] \(item.source)")
		}
	}

	func testTimeDuration() {
		let dur1 = TimeDuration.parse("23h44m")
		let dur2 = TimeDuration.parse("44m")
		XCTAssertEqual(TimeDuration.hours(23), dur1 - dur2)
		XCTAssertEqual(TimeDuration.minutes(88), dur2 * 2)
		XCTAssertEqual(TimeDuration.minutes(22), dur2 / 2)
		XCTAssertEqual(TimeDuration.parse("9s999999us"), TimeDuration(seconds: 10, nanoseconds: -1000))
		XCTAssertEqual(TimeDuration.parse("-10s1us"), TimeDuration(seconds: -10, nanoseconds: 1000))
		XCTAssertEqual(TimeDuration.parse("-9s999999us"),
					   TimeDuration(seconds: -10, nanoseconds: -1000))
		XCTAssertEqual(TimeDuration.parse("-999999us"),
					   TimeDuration(seconds: 1, nanoseconds: -1000001000))
		XCTAssertEqual(TimeDuration.parse("999999us"),
					   TimeDuration(seconds: 2, nanoseconds: -1000001000))
		XCTAssertEqual(TimeDuration.parse("1us"),
					   TimeDuration(seconds: -1, nanoseconds: 1000001000))
	}
	
	func testTime() {
		XCTAssertEqual(Time.Month.april, Time.Month(rawValue: 4))
		XCTAssertEqual(Time.Month.april, Time.Month(index: 3))
		XCTAssertEqual(Time.Month.april, Time.Month(index: -21))
		XCTAssertEqual(Time.Month.april, Time.Month(index: 15))
		XCTAssertEqual(Time.Month.april, Time.Month(named: "April"))
		XCTAssertEqual(Time.Month.april, Time.Month(shortName: "Apr"))
		XCTAssertEqual(3, Time.Month.april.index)
		XCTAssertEqual(4, Time.Month.april.advanced(1).index)
		XCTAssertEqual(3, Time.Month.april.advanced(12).index)

		let timeOver = Time(seconds: 3, nano: -2_123_456_789)
		let timeResult = Time(seconds: 0, nano: 876_543_211)
		XCTAssert(timeOver == timeResult)
		
		let t1 = Time(year: 2020, month: .october, day: 1, hour: 0, minute: 10, second: 10, nano: 2, offset: 0)
		XCTAssertEqual(t1.clock, .init(hour: 0, minute: 10, second: 10))
		XCTAssertEqual(t1.add(years: 1, months: 1, days: 1).date,
					   .init(year: 2021, month: .november, day: 2))
		XCTAssertEqual(t1.add(years: 1, months: 1, days: 100).date,
					   .init(year: 2022, month: .february, day: 9))
		XCTAssertEqual(t1.weekday, .thursday)
		XCTAssertEqual(t1.weekday.shortName, "Thu")
		XCTAssertEqual(t1.weekday.name, "Thursday")
		let te = Time(year: 20221014, month: 0, day: 0, hour: 0, minute: 0, second: 0, nano: 0, offset: 0)
		print(te.asDate)
		do {
			let t = Time(year: 2020, month: .october, day: 1, hour: 0, minute: 10, second: 10, nano: 10002003, offset: 0)
			for diffTo in [
				.zero,
				Time(year: -4000, month: .october, day: 1),
			] {
				let dur = t.diff(diffTo)
				let sec = dur.decimalSeconds
				print("\(dur) ns=\(dur.nanoseconds) us=\(dur.microseconds) ms=\(dur.milliseconds)\n\ts=\(sec) min=\(dur.minutes) hour=\(dur.hours)")
				XCTAssertEqual(t, diffTo.after(dur))
			}
		}
	}

	func testTimeParser() {
		struct Case {
			let string: String
			let expect: String
			let layout: TimeLayout

			init(string: String, expect: String, _ layout: TimeLayout) {
				self.string = string
				self.expect = expect
				self.layout = layout
			}
		}
		let cases: [Case] = [
			.init(string: "0001-01-01T00:00:00Z",
				  expect: "0001-01-01T00:00:00.000Z", .rfc3339Millisecond),
			.init(string: "2020112-4-2T13:00:03Z",
				  expect: "-292277020430-01-01T00:00:00.000Z", .rfc3339Millisecond), // RFC3339
			.init(string: "2022-10-11",
				  expect: "2022-10-11T00:00:00.000Z", .rfc3339Millisecond),
			.init(string: "2022-10-11 13:43:15.324 +08:00",
				  expect: "2022-10-11T13:43:15.324+08:00", .rfc3339Millisecond), // from postgres
			.init(string: "2022-10-11 13:43:15 +0000",
				  expect: "2022-10-11T13:43:15.000Z", .rfc3339Millisecond), // from postgres
			.init(string: "2022-10-11 13:43:15 +0800",
				  expect: "2022-10-11T13:43:15.000+08:00", .rfc3339Millisecond), // from postgres
			.init(string: "2022-10-11 13:43:15 +08:00",
				  expect: "2022-10-11T13:43:15.000+08:00", .rfc3339Millisecond), // from postgres
			.init(string: "2020-11-2T13:00:03+0200",
				  expect: "2020-11-02T13:00:03.000+02:00", .rfc3339Millisecond), // RFC3339
			.init(string: "2020-11-2T13:00:03Z",
				  expect: "2020-11-02T13:00:03.000Z", .rfc3339Millisecond), // RFC3339
			.init(string: "2020-11-2T13:00:03.366Z",
				  expect: "2020-11-02T13:00:03.366Z", .rfc3339Millisecond), // RFC3339
		]
		for it in cases {
			print("*  \(it.expect) from \(it.string)")
			do {
				let time = try Time.parse(date: it.string)
				let formatted = it.layout.format(time)
				print(">> \(formatted) \(it.expect == formatted ? "✅" : "❌")")
			} catch {
				print("!! \(error)")
			}
			do {
				let time = try Time.parse(date: it.string, layout: it.layout)
				let formatted = it.layout.format(time)
				print(">> \(formatted) \(it.expect == formatted ? "✅" : "❌")")
			} catch {
				print("!! \(error)")
			}
		}
	}

	func testTimeFormat() {
		let time = Time(year: 2020, month: .october, day: 1, hour: 13, minute: 10, second: 10, nano: 31_314_622, offset: 28800)
		for layout in [
			.ansiC,
			.rfc3339,
			.rfc3339Millisecond,
			.rfc3339Nanosecond,
			.rfc822,
			.rfc822Z,
			.rfc850,
			.init(components: [.hour(.ampm), .string(":"), .minute, .ampm]),
		] as [TimeLayout] {
			print(layout.format(time))
		}
		measure {
			_ = TimeLayout.rfc3339Millisecond.format(time)
		}
	}

	func testSeconds() {
		print(TimeDuration.nanoseconds(.max).nanoseconds / TimeDuration.nanosecondsPerSecond)
//		print(TimeLayout.rfc3339Millisecond.format(.init(seconds: 63817401930, nano: 206000000)))
	}

	func testTimeRange() {
		let range = OptionalRange(lower: Time(), upper: Time(), closed: false)
		print(range.description)
	}
}

extension Time: CustomStringConvertible {
	public var description: String {
		TimeLayout.rfc3339.format(self)
	}
}
