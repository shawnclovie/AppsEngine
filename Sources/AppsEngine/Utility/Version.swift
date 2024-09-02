//
//  Version.swift
//  Spot
//
//  Created by Shawn Clovie on 1/5/16.
//  Copyright © 2016 Shawn Clovie. All rights reserved.
//

import Foundation

/// Version with some code numbers.
public struct Version: LosslessStringConvertible {
	public static let separator = "."
	
	public typealias NumberType = UInt
	
	public var numbers: [NumberType] = []
	
	public init(_ description: String) {
		self.init(description[...], separator: Self.separator)
	}
	
	/// Initialize version with string like 1.3.0
	///
	/// - Parameters:
	///   - version: Version string
	///   - separator: Separator, default is ".".
	public init(_ version: String, separator: String) {
		self.init(version[...], separator: separator)
	}
	
	public init(_ ver: String.SubSequence, separator: String = separator) {
		let components = ver.components(separatedBy: separator)
		for comp in components {
			if let number = NumberType(comp) {
				numbers.append(number)
			}
		}
	}
	
	public init(_ version: NumberType...) {
		numbers.append(contentsOf: version)
	}
	
	/// Get version code for index.
	///
	/// - parameter index: Code number index
	///
	/// - returns: Code number, or 0 while index not in range (0..<count of numbers).
	public subscript(index: Int) -> NumberType {
		index < numbers.count - 1 ? numbers[index] : 0
	}
	
	public var description: String {
		numbers.map{String($0)}.joined(separator: Self.separator)
	}
	
	/// Convert version as one number like 20509 from 2.5.9
	/// - Parameters:
	///   - count: Count of segment, should >= 1
	///   - length: Length of each segment, should >= 1
	public func segmentNumber(count: Int = 3, length: Int = 2) -> NumberType {
		let count = max(count, 1)
		let length = max(length, 1)
		var num: NumberType = 0
		for i in 0..<count {
			let p = pow(10, Double(count - i - 1) * Double(length))
			num += self[i] * NumberType(p)
		}
		return num
	}
	
	/// Compare two version object.
	///
	/// - Parameters:
	///   - ver1: Version1
	///   - ver2: Version2
	///
	/// - Returns: Comparison result
	public func compare(to ver2: Version) -> ComparisonResult {
		let len1 = numbers.count
		let len2 = ver2.numbers.count
		var v1: NumberType = 0
		var v2: NumberType = 0
		for i in 0..<max(len1, len2) {
			v1 = self[i]
			v2 = ver2[i]
			if v1 != v2 {
				return v1 > v2 ? .orderedDescending : .orderedAscending
			}
		}
		return .orderedSame
	}
	
	public static func compare(_ ver1: String, toVersion ver2: String) -> ComparisonResult {
		Version(ver1).compare(to: Version(ver2))
	}
}

extension Version: Comparable, Equatable {
	public static func ==(l: Self, r: Self) -> Bool {
		l.compare(to: r) == .orderedSame
	}
	
	public static func >(l: Self, r: Self) -> Bool {
		l.compare(to: r) == .orderedDescending
	}
	
	public static func >=(l: Self, r: Self) -> Bool {
		l.compare(to: r) != .orderedAscending
	}
	
	public static func <(l: Self, r: Self) -> Bool {
		l.compare(to: r) == .orderedAscending
	}
	
	public static func <=(l: Self, r: Self) -> Bool {
		l.compare(to: r) != .orderedDescending
	}
}

extension Version: Codable {
	public init(from decoder: Decoder) throws {
		let container = try decoder.singleValueContainer()
		let text = try container.decode(String.self)
		self.init(text, separator: Self.separator)
	}
	
	public func encode(to encoder: Encoder) throws {
		var container = encoder.singleValueContainer()
		try container.encode(description)
	}
}

extension Version: JSONCodable {
	public init(from json: JSON) throws {
		guard case .string(let text) = json else {
			throw WrapError(.invalid_parameter, "\(Self.self) should be string")
		}
		self.init(text, separator: Self.separator)
	}

	public var jsonValue: JSON {
		.string(description)
	}
}
