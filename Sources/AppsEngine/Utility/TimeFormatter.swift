//
//  TimeFormatter.swift
//  
//
//  Created by Shawn Clovie on 12/10/2022.
//

import Foundation

public struct TimeLayout: Sendable {
	/// `Mon Jan _2 15:04:05 2006`
	public static let ansiC = Self(dateLeadingZero: false, components: [
		.weekday(.short), .string(" "),
		.month(.short), .string(" "),
		.day, .string(" "),
		.hour(), .string(":"), .minute, .string(":"), .second, .string(" "),
		.year(.full),
	])
	
	/// ISO8601 or RFC3339: `2006-01-02T15:04:05-0700`
	public static let rfc3339 = Self(components: [
		.year(.full), .string("-"), .month(.digital), .string("-"), .day,
		.anyString(["T", " "]),
		.hour(), .string(":"), .minute, .string(":"), .second,
		.timezone(colon: true),
	])

	public static let rfc3339Millisecond = Self(components: [
		.year(.full), .string("-"), .month(.digital), .string("-"), .day,
		.anyString(["T", " "]),
		.hour(), .string(":"), .minute, .string(":"), .second,
		.formattingString("."), .millisecond,
		.timezone(colon: true),
	])

	public static let rfc3339Nanosecond = Self(components: [
		.year(.full), .string("-"), .month(.digital), .string("-"), .day,
		.anyString(["T", " "]),
		.hour(), .string(":"), .minute, .string(":"), .second,
		.formattingString("."), .nanosecond,
		.timezone(colon: true),
	])
	
	/// `02 Jan 06 15:04 MST`
	public static let rfc822 = Self(components: [
		.year(.full), .string(" "), .month(.short), .string(" "), .day,
		.string(" "), .hour(), .string(":"), .minute, .string(" MST"),
	])
	
	/// `02 Jan 06 15:04 -07:00`
	public static let rfc822Z = Self(components: [
		.year(.full), .string(" "), .month(.short), .string(" "), .day,
		.string(" "), .hour(), .string(":"), .minute, .timezone(),
	])

	/// `Monday, 02-Jan-06 15:04:05 MST`
	public static let rfc850 = Self(components: [
		.weekday(.name), .string(", "),
		.year(.inCentry), .string("-"), .month(.short), .string("-"), .day,
		.string(" "), .hour(), .string(":"), .minute, .string(":"), .second,
		.string(" MST"),
	])

	/// `2006-01-02`
	public static let date = Self(components: [
		.year(.full), .string("-"), .month(.digital), .string("-"), .day,
	])

	/// `15:04:05`
	public static let time = Self(components: [
		.hour(), .string(":"), .minute, .string(":"), .second,
	])

	/// `2006-01-02 15:04:05`
	public static let datetime = Self(components: [
		.year(.full), .string("-"), .month(.digital), .string("-"), .day,
		.string(" "),
		.hour(), .string(":"), .minute, .string(":"), .second,
	])
	
	public enum Component: Sendable {
		case string(String)
		case formattingString(String)
		/// - Formatting: use first string
		/// - Parsing: match any of strings
		case anyString([String])
		case year(YearStyle)
		case month(MonthStyle)
		case day
		case weekday(WeekdayStyle)
		case ampm
		case hour(HourStyle = .h24)
		case minute
		case second
		/// formatting only
		case millisecond
		/// formatting only
		case nanosecond
		case timezone(gmt: String = "Z", colon: Bool = false)
	}
	
	public enum YearStyle: Sendable {
		case full, inCentry

		var digitCount: Int {
			switch self {
			case .full:		return 4
			case .inCentry:	return 2
			}
		}
	}
	
	public enum MonthStyle: Sendable {
		case digital, name, short
	}
	
	public enum WeekdayStyle: Sendable {
		case name, short
	}
	
	public enum HourStyle: Sendable {
		case h24, ampm
		
		func hour(_ hour: Int) -> Int {
			switch self {
			case .h24:
				return hour
			case .ampm:
				return hour > 12 ? hour - 12 : hour
			}
		}
	}

	public var dateLeadingZero: Bool
	public var timeLeadingZero: Bool
	public var components: [Component]
	
	public init(dateLeadingZero: Bool = true, timeLeadingZero: Bool = true, components: [Component]) {
		self.dateLeadingZero = dateLeadingZero
		self.timeLeadingZero = timeLeadingZero
		self.components = components
	}
	
	public func format(_ time: Time) -> String {
		var str = ""
		let date = time.date
		let clock = time.clock
		for component in components {
			switch component {
			case .formattingString(let s):
				str += s
			case .string(let s):
				str += s
			case .anyString(let ss):
				if !ss.isEmpty {
					str += ss[0]
				}
			case .year(let style):
				let v: Int
				switch style {
				case .full:
					v = date.year
				case .inCentry:
					v = date.year - date.year / 100 * 100
				}
				let s = "\(v)"
				let leadingZeroCount = style.digitCount - s.count
				if leadingZeroCount > 0 {
					str += String(repeating: "0", count: leadingZeroCount) + s
				} else {
					str += s
				}
			case .month(let style):
				switch style {
				case .digital:
					str += dateLeadingZero ? Self.format(Int(date.month.rawValue), leadingZero: 2) : "\(date.month.rawValue)"
				case .name:
					str += date.month.name
				case .short:
					str += date.month.shortName
				}
			case .day:
				str += dateLeadingZero ? Self.format(date.day, leadingZero: 2) : "\(date.day)"
			case .weekday(let style):
				let wd = time.weekday
				switch style {
				case .name:
					str += wd.name
				case .short:
					str += wd.shortName
				}
			case .ampm:
				str += clock.hour >= 12 ? "PM" : "AM"
			case .hour(let style):
				let hour = style.hour(clock.hour)
				str += timeLeadingZero ? Self.format(hour, leadingZero: 2) : "\(hour)"
			case .minute:
				str += timeLeadingZero ? Self.format(clock.minute, leadingZero: 2) : "\(clock.minute)"
			case .second:
				str += timeLeadingZero ? Self.format(clock.second, leadingZero: 2) : "\(clock.second)"
			case .millisecond:
				let clock = time.clock
				str += Self.format(clock.millisecond, leadingZero: 3)
			case .nanosecond:
				str += Self.format(Int(time.nanoseconds), leadingZero: 9)
			case .timezone(let gmt, let colon):
				str += Self.formatOffset(time.offset, zero: gmt, colon: colon)
			}
		}
		return str
	}
	
	public var dateFormat: String {
		var str = ""
		for component in components {
			switch component {
			case .formattingString(let s):
				str += "[\(s)]"
			case .string(let s):
				str += s
			case .anyString(let ss):
				str += "[\(ss.joined(separator: "|"))]"
			case .year(let style):
				switch style {
				case .full:
					str += "yyyy"
				case .inCentry:
					str += "yy"
				}
			case .month(let style):
				switch style {
				case .digital:
					str += dateLeadingZero ? "MM" : "M"
				case .name:
					str += "MMMM"
				case .short:
					str += "MMM"
				}
			case .day:
				str += dateLeadingZero ? "dd" : "d"
			case .weekday(let style):
				switch style {
				case .name:
					str += "E"
				case .short:
					str += "EEE"
				}
			case .ampm:
				str += "a"
			case .hour(_):
				str += timeLeadingZero ? "HH" : "H"
			case .minute:
				str += timeLeadingZero ? "mm" : "m"
			case .second:
				str += timeLeadingZero ? "ss" : "ss"
			case .millisecond:
				str += "SSS"
			case .nanosecond:
				break
			case .timezone(_, let colon):
				str += colon ? "XXX" : "XX"
			}
		}
		return str
	}
	
	static func format(_ number: Int, leadingZero: UInt8) -> String {
		let str = "\(number)"
		let zeroLen = Int(leadingZero) - str.count
		return zeroLen > 0 ? String(repeating: "0", count: zeroLen) + str : str
	}
	
	static func formatOffset(_ offset: Int, zero: String = "Z", colon: Bool) -> String {
		if offset == 0 {
			return zero
		}
		let _offset = abs(offset) / 60
		let hOffset = _offset / 60
		let mOffset = _offset % 60
		let symbol = offset < 0 ? "-" : "+"
		return String(format: "%@%02d\(colon ? ":" : "")%02d", symbol, hOffset, mOffset)
	}
}

extension Time {
	public struct Parser {
		enum NoLayoutStep: UInt8 { case none, date, all }

		var year: Int?
		var month: Int?
		var day: Int?
		var isPM = false
		var hour: Int?
		var minute: Int?
		var second: Int?
		var nanosecond: Int?
		var offset: Int?

		public init() {}

		mutating func scan(_ string: String) -> NoLayoutStep {
			let scanner = Scanner(string: string)
			scanner.charactersToBeSkipped = nil
			guard let year = scanner.scanInt() else { return .none }
			self.year = year
			_ = scanner.scanCharacter()
			guard let month = scanner.scanInt() else { return .none }
			self.month = month
			_ = scanner.scanCharacter()
			guard let day = scanner.scanInt() else { return .none }
			self.day = day
			_ = scanner.scanCharacter()

			guard let hour = scanner.scanInt() else { return .date }
			self.hour = hour
			_ = scanner.scanCharacter()
			guard let minute = scanner.scanInt() else { return .date }
			self.minute = minute
			_ = scanner.scanCharacter()
			guard let sec = scanner.scanSecond() else { return .date }
			second = sec.second
			nanosecond = sec.nanosecond
			let rest = string[scanner.currentIndex...]
				.trimmingCharacters(in: .whitespacesAndNewlines)
				.replacingOccurrences(of: ":", with: "")
			if let sign = rest.first,
			   sign != "Z" && rest.count >= 5,
			   let offset = Int(rest.dropFirst()) {
				setOffset(hour: offset, minute: 0)
			}
			return .all
		}

		/// - Returns: missing component
		mutating func scan(_ string: String, layout: TimeLayout) -> String? {
			let scanner = Scanner(string: string)
			scanner.charactersToBeSkipped = nil
			for i in 0..<layout.components.count {
				switch layout.components[i] {
				case .formattingString(_):
					break
				case .string(let s):
					if scanner.scanString(s) == nil {
						return "[\(i)]string(\(s))"
					}
				case .anyString(let ss):
					var v = ""
					repeat {
						guard let ch = scanner.scanCharacter() else {
							return "[\(i)]anyString(\(ss.joined(separator: "|")))v='\(v)'"
						}
						v.append(ch)
						if ss.firstIndex(of: v) != nil {
							break
						}
					} while true
				case .year(_):
					guard let v = scanner.scanInt() else {
						return "[\(i)]year"
					}
					year = v
				case .month(let monthStyle):
					switch monthStyle {
					case .digital:
						guard let v = scanner.scanInt() else {
							return "[\(i)]month(digital)"
						}
						month = v
					case .name:
						var v = ""
						repeat {
							guard let ch = scanner.scanCharacter() else {
								return "[\(i)]month(name)"
							}
							v.append(ch)
							if let index = Time.Month.names.firstIndex(of: v) {
								month = index + 1
								break
							}
						} while true
					case .short:
						var v = ""
						for _ in 0..<3 {
							if let ch = scanner.scanCharacter() {
								v.append(ch)
							} else {
								break
							}
						}
						guard let index = Time.Month.shortNames.firstIndex(of: v) else {
							return "[\(i)]month(short)"
						}
						month = index + 1
					}
				case .day:
					guard let v = scanner.scanInt() else {
						return "[\(i)]day"
					}
					day = v
				case .weekday(_):
					var v = ""
					repeat {
						guard let ch = scanner.scanCharacter() else {
							return "[\(i)]weekday"
						}
						v.append(ch)
						if Time.Weekday.names.firstIndex(of: v) != nil {
							break
						}
					} while true
				case .ampm:
					guard let ch = scanner.scanCharacter()?.uppercased() else {
						return "[\(i)]ampm[1]"
					}
					isPM = ch == "P"
					if scanner.scanCharacter() == nil {
						return "[\(i)]ampm[2]"
					}
				case .hour(_):
					guard let v = scanner.scanInt() else {
						return "[\(i)]hour"
					}
					hour = v
				case .minute:
					guard let v = scanner.scanInt() else {
						return "[\(i)]minute"
					}
					minute = v
				case .second:
					guard let v = scanner.scanSecond() else {
						return "[\(i)]second"
					}
					second = v.second
					nanosecond = v.nanosecond
				case .millisecond:
					break
				case .nanosecond:
					break
				case .timezone(let gmt, _):
					scanner.skipCharacters(in: " ")
					guard let sign = scanner.scanCharacter(),
						  String(sign) != gmt,
						  var zone = scanner.scanCharacters(from: .init(charactersIn: "0123456789:")) else {
						break
					}
					zone = zone.replacingOccurrences(of: ":", with: "")
					guard let num = Int(zone) else {
						break
					}
					setOffset(hour: num, minute: 0)
				}
				if scanner.isAtEnd {
					break
				}
			}
			return nil
		}

		private mutating func setOffset(hour: Int, minute: Int) {
			if hour != 0 || minute != 0 {
				let isMinus = hour < 0 || minute < 0
				var hOffset = abs(hour)
				var mOffset = abs(minute)
				if hOffset > 100 {
					mOffset = hOffset - (hOffset / 100 * 100)
					hOffset /= 100
				}
				offset = (hOffset * 3600 + mOffset * 60) * (isMinus ? -1 : 1)
			} else {
				offset = 0
			}
		}
	}

	public static func parse(date string: String, layout: TimeLayout? = nil) throws -> Time {
		var parser = Parser()
		if let layout {
			if let missing = parser.scan(string, layout: layout) {
				throw WrapError(.invalid_parameter, [
					"error": .string(missing),
					"date": .string(string),
					"layout": .string(layout.dateFormat),
				])
			}
		} else {
			if parser.scan(string) == .none {
				throw WrapError(.invalid_parameter, [
					"error": .string("no date"),
					"date": .string(string),
				])
			}
		}
		return Time(year: parser.year ?? 0,
					month: parser.month ?? 0,
					day: parser.day ?? 0,
					hour: parser.hour ?? 0,
					minute: parser.minute ?? 0,
					second: parser.second ?? 0,
					nano: parser.nanosecond ?? 0,
					offset: parser.offset ?? 0)
	}
}

private extension Scanner {
	var currentCharacter: Character? {
		currentIndex < string.endIndex ? string[currentIndex] : nil
	}

	func skipCharacters(in chSet: String) {
		while let ch = currentCharacter, chSet.contains(ch) {
			_ = scanCharacter()
		}
	}

	func scanSecond() -> (second: Int, nanosecond: Int?)? {
		guard let v = scanInt() else {
			return nil
		}
		let second = v
		if currentCharacter == "." {
			_ = scanCharacter()
			if let s = scanCharacters(from: .init(charactersIn: "0123456789")),
			   let num = Int(s) {
				let nanosecond = s.count > 3 ? num : num * Int(TimeDuration.nanosecondsPerMillisecond)
				return (second, nanosecond)
			}
		}
		return (second, nil)
	}
}
