import Foundation
import SQLKit
import NIOPosix
import struct NIO.TimeAmount

extension Time {
	public func isSameDay(_ other: Time) -> Bool {
		let d1 = date
		let d2 = other.date
		return d1.year == d2.year && d1.month == d2.month && d1.day == d2.day
	}

	public init?(parse string: String) {
		do {
			self = try Time.parse(date: string)
		} catch {
			return nil
		}
	}
	
	public var rfc3339String: String {
		TimeLayout.rfc3339Millisecond.format(self)
	}
}

extension Time: Codable {
	public init(from decoder: Decoder) throws {
		let text = try decoder.singleValueContainer().decode(String.self)
		self = try Time.parse(date: text)
	}

	public func encode(to encoder: Encoder) throws {
		var container = encoder.singleValueContainer()
		try container.encode(rfc3339String)
	}
}

extension Time: JSONCodable {
	public init(from json: JSON) throws {
		guard case .string(let text) = json else {
			throw WrapError(.invalid_parameter, [
				Keys.description: .string("\(Self.self) should be ISO8601 or RFC3339 string"),
				"value": json,
			])
		}
		self = try Time.parse(date: text)
	}
	
	public var jsonValue: JSON {
		.string(rfc3339String)
	}
}

extension TimeDuration {
	public var amount: TimeAmount {
		.nanoseconds(nanoseconds)
	}
}
