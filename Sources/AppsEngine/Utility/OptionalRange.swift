//
//  OptionalRange.swift
//
//
//  Created by Shawn Clovie on 2024/7/26.
//

import Foundation

public let optionalRangeSeparator: Character = "-"

public struct OptionalRange<Bound: Comparable> {
	public static var unbounded: Self {
		Self.init(lower: nil, upper: nil, closed: false)
	}

	public var lowerBound: Bound?
	public var upperBound: Bound?
	public var closed: Bool

	public init(lower: Bound?, upper: Bound?, closed: Bool) {
		lowerBound = lower
		upperBound = upper
		self.closed = closed
	}

	public init(_ range: ClosedRange<Bound>) {
		self.init(lower: range.lowerBound, upper: range.upperBound, closed: true)
	}

	public init(_ range: Range<Bound>) {
		self.init(lower: range.lowerBound, upper: range.upperBound, closed: false)
	}

	public var isEmpty: Bool {
		guard let lower = lowerBound, let upper = upperBound else {
			return false
		}
		return lower == upper
	}

	public func contains(_ value: Bound) -> Bool {
		if let lowerBound = lowerBound, value < lowerBound {
			return false
		}
		if let upperBound = upperBound {
			return closed ? value <= upperBound : value < upperBound
		}
		return true
	}
}

extension OptionalRange: Equatable where Bound: Equatable {
}

extension OptionalRange: Codable, LosslessStringConvertible
where Bound: Codable & LosslessStringConvertible {
	public init(from decoder: Decoder) throws {
		let container = try decoder.singleValueContainer()
		self.init(try container.decode(String.self))
	}

	public func encode(to encoder: Encoder) throws {
		var container = encoder.singleValueContainer()
		try container.encode(description)
	}

	public init(_ description: String) {
		if description.isEmpty {
			self.init(lower: nil, upper: nil, closed: false)
		} else {
			let comps = description.split(separator: optionalRangeSeparator, maxSplits: 2, omittingEmptySubsequences: false)
			self.init(lower: comps[0].isEmpty ? nil : Bound(String(comps[0])),
					  upper: comps.count < 2 || comps[1].isEmpty ? nil : Bound(String(comps[1])),
					  closed: true)
		}
	}
}

extension OptionalRange: CustomStringConvertible
where Bound: CustomStringConvertible {
	public var description: String {
		if lowerBound == nil && upperBound == nil {
			return ""
		}
		var result = lowerBound?.description ?? ""
		result.append(optionalRangeSeparator)
		if let upper = upperBound {
			result += upper.description
		}
		return result
	}
}

extension OptionalRange: JSONCodable
where Bound: Codable & LosslessStringConvertible {
	public init(from json: JSON) throws {
		guard case .string(let text) = json else {
			throw WrapError(.invalid_parameter, "\(Self.self) should be string")
		}
		self.init(text)
	}

	public var jsonValue: JSON {
		.string(description)
	}
}
