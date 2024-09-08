//
//  JSON.swift
//  
//
//  Created by Shawn Clovie on 10/6/2022.
//

import Foundation
import NIOCore

public enum JSON : Sendable {
	public static func number<T: FixedWidthInteger & SignedInteger>(_ value: T) -> JSON {
		.number(Decimal(Int64(value)))
	}

	public static func number<T: FixedWidthInteger & UnsignedInteger>(_ value: T) -> JSON {
		.number(Decimal(UInt64(value)))
	}

	public static func number<T: BinaryFloatingPoint>(_ value: T) -> JSON {
		.number(Decimal(Double(value)))
	}

	case null
	case number(Decimal)
	case string(String)
	case bool(Bool)
	case array([Self])
	case object([String: Self])
}

extension JSON {
	/// Initialize with `value`, if `value` cannot convert to `JSON`, it would be `.null`.
	public init(from value: Any?) {
		switch value {
		case let v as JSONEncodable:
			self = v.jsonValue
		case let vs as [Any]:
			self = .array(vs.map(Self.init))
		case let vs as [AnyHashable: Any]:
			var obj: [String: JSON] = [:]
			obj.reserveCapacity(vs.count)
			for (key, value) in vs {
				obj[key.description] = Self.init(from: value)
			}
			self = .object(obj)
		default:
			self = .null
		}
	}

	/// Get bool value if `self` is `.bool`
	public var boolValue: Bool? {
		if case let .bool(v) = self {
			return v
		}
		return nil
	}

	/// Get number value if `self` is `.number`
	public var numberValue: Decimal? {
		if case let .number(v) = self {
			return v
		}
		return nil
	}

	/// Get string value if `self` is `.string`
	public var stringValue: String? {
		if case let .string(v) = self {
			return v
		}
		return nil
	}

	/// Get array value if `self` is `.array`
	public var arrayValue: [JSON]? {
		if case let .array(v) = self {
			return v
		}
		return nil
	}

	/// Get object value if `self` is `.object`
	public var objectValue: [String: JSON]? {
		if case let .object(v) = self {
			return v
		}
		return nil
	}
	
	public var rawValue: Any? {
		switch self {
		case .null:
			return nil
		case .number(let v):
			return v
		case .string(let v):
			return v
		case .bool(let v):
			return v
		case .array(let vs):
			return vs.map(\.rawValue)
		case .object(let vs):
			var raw: [String: Any] = [:]
			raw.reserveCapacity(vs.count)
			for (k, v) in vs {
				raw[k] = v.rawValue
			}
			return raw
		}
	}

	public var valueAsInt64: Int64? {
		switch self {
		case .number(let v):
			return (v as NSDecimalNumber).int64Value
		case .string(let v):
			return Int64(v)
		default:
			return nil
		}
	}

	public var valueAsUInt64: UInt64? {
		switch self {
		case .number(let v):
			return (v as NSDecimalNumber).uint64Value
		case .string(let v):
			return UInt64(v)
		default:
			return nil
		}
	}

	public var valueAsDouble: Double? {
		switch self {
		case .number(let v):
			return (v as NSDecimalNumber).doubleValue
		case .string(let v):
			return Double(v)
		default:
			return nil
		}
	}

	public subscript(index: Int) -> Self {
		get {
			guard index >= 0, let vs = arrayValue else {
				return .null
			}
			return vs[index]
		}
		set {
			switch self {
			case .array(var vs):
				vs[index] = newValue
				self = .array(vs)
			default:
				preconditionFailure("access on [\(index)] on non-array value")
			}
		}
	}
	
	public mutating func append(_ newValue: Self) {
		switch self {
		case .array(var vs):
			vs.append(newValue)
			self = .array(vs)
		default:
			preconditionFailure("append on non-array value")
		}
	}
	
	public mutating func append<Elements: Sequence>(contentsOf newValue: Elements)
	where Elements.Element == Self {
		switch self {
		case .array(var vs):
			vs.append(contentsOf: newValue)
			self = .array(vs)
		default:
			preconditionFailure("append contents on non-array value")
		}
	}
	
	public mutating func insert(_ newValue: Self, at: Int) {
		switch self {
		case .array(var vs):
			vs.insert(newValue, at: at)
			self = .array(vs)
		default:
			preconditionFailure("insert at [\(at)] on non-array value")
		}
	}

	@inlinable
	public subscript(keys: CollectionKey...) -> Self {
		valueFor(keys: keys[...])
	}

	public subscript(key: String) -> Self {
		get { self.valueFor(keys: [.key(key)]) }
		set {
			switch self {
			case .object(var vs):
				vs[key] = newValue
				self = .object(vs)
			default:
				preconditionFailure("access [\(key)] on non-object value")
			}
		}
	}

	public enum CollectionKey: ExpressibleByIntegerLiteral, ExpressibleByStringLiteral {
		case index(_ index: Int)
		case key(_ key: String)

		public init(stringLiteral value: StringLiteralType) {
			self = .key(value)
		}

		public init(integerLiteral value: IntegerLiteralType) {
			self = .index(value)
		}
	}

	@inlinable
	public func valueFor(keys: CollectionKey...) -> Self {
		valueFor(keys: keys[...])
	}
	
	public func valueFor(keys: ArraySlice<CollectionKey>) -> Self {
		switch keys.first {
		case nil:
			return .null
		case .index(let index):
			guard case .array(let array) = self, index < array.count else {
				return .null
			}
			let value = array[index]
			return keys.count == 1 ? value : value.valueFor(keys: keys.dropFirst())
		case .key(let key):
			guard case .object(let vs) = self,
				  let value = vs[key] else {
				return .null
			}
			return keys.count == 1 ? value : value.valueFor(keys: keys.dropFirst())
		}
	}
	
	public mutating func setValues(_ newValues: [String: Self]) {
		switch self {
		case .object(var vs):
			vs.setValues(newValues)
			self = .object(vs)
		default:
			preconditionFailure("setValues on non-object value")
		}
	}
	
	public struct Decoder {
		public init() {}

		public func decode(_ str: some StringProtocol) throws -> JSON {
			try decode(Data(str.utf8))
		}

		public func decode(_ data: Data) throws -> JSON {
			let decoder = JSONDecoder()
			if #available(macOS 12.0, iOS 15.0, *) {
				decoder.allowsJSON5 = true
			}
			return try decoder.decode(JSON.self, from: data)
		}
	}

	public struct Encoder {
		public var options: JSONEncoder.OutputFormatting
		
		public init(options: JSONEncoder.OutputFormatting = []) {
			self.options = options
		}
		
		public func encode(_ value: JSON) -> String {
			switch value {
			case .null:
				return Const.null.description
			case .number(let v):
				return v.description
			case .string(let v):
				return escape(v)
			case .bool(let v):
				return (v ? Const.true : Const.false).description
			case .array(let vs):
				var buf = ByteBuffer()
				write(value, to: &buf)
				return buf.readString(length: buf.readableBytes, encoding: .utf8)
					?? "[\(vs.map(\.description).joined(separator: ","))]"
			case .object(let vs):
				var buf = ByteBuffer()
				write(value, to: &buf)
				return buf.readString(length: buf.readableBytes, encoding: .utf8)
					?? "{\(vs.map{ "\(escape($0.key)):\($0.value)" }.joined(separator: ","))}"
			}
		}
		
		public func write(_ value: JSON, to buf: inout ByteBuffer, indent: UInt = 0) {
			switch value {
			case .null:
				buf.writeStaticString(Const.null)
			case .number(let v):
				buf.writeString(v.description)
			case .string(let v):
				buf.writeString(escape(v))
			case .bool(let v):
				buf.writeStaticString(v ? Const.true : Const.false)
			case .array(let array):
				write(array: array, into: &buf, indent: indent)
			case .object(let vs):
				write(object: vs, into: &buf, indent: indent)
			}
		}
		
		private func write(array: [JSON], into buf: inout ByteBuffer, indent: UInt) {
			let pretty = prettyPrint
			buf.writeStaticString(Const.bracketSquareL)
			var first = true
			for v in array {
				if first {
					first = false
				} else {
					buf.writeStaticString(Const.comma)
				}
				if pretty {
					buf.writeStaticString(Const.lf)
					buf.writeString(Const.indent(count: indent + 1))
				}
				write(v, to: &buf, indent: indent + 1)
			}
			if pretty && !array.isEmpty {
				buf.writeStaticString(Const.lf)
				buf.writeString(Const.indent(count: indent))
			}
			buf.writeStaticString(Const.bracketSquareR)
		}
		
		private func write(object: [String: JSON], into buf: inout ByteBuffer, indent: UInt) {
			buf.writeStaticString(Const.bracketCurlyL)
			var first = true
			if options.contains(.sortedKeys) {
				let keys = Array(object.keys).sorted()
				for k in keys {
					guard let v = object[k] else {
						continue
					}
					if first {
						first = false
					} else {
						buf.writeStaticString(Const.comma)
					}
					write(objectEntry: k, value: v, into: &buf, indent: indent + 1)
				}
			} else {
				for (k, v) in object {
					if first {
						first = false
					} else {
						buf.writeStaticString(Const.comma)
					}
					write(objectEntry: k, value: v, into: &buf, indent: indent + 1)
				}
			}
			if prettyPrint && !object.isEmpty {
				buf.writeStaticString(Const.lf)
				buf.writeString(Const.indent(count: indent))
			}
			buf.writeStaticString(Const.bracketCurlyR)
		}
		
		private func write(objectEntry key: String, value: JSON, into buf: inout ByteBuffer, indent: UInt) {
			if prettyPrint {
				buf.writeStaticString(Const.lf)
				buf.writeString(Const.indent(count: indent))
			}
			buf.writeString(escape(key))
			buf.writeStaticString(Const.colon)
			if prettyPrint {
				buf.writeStaticString(Const.space)
			}
			write(value, to: &buf, indent: indent)
		}
		
		@inline(__always)
		private func escape(_ string: String) -> String {
			Self.escape(string, escapingSlashes: options.contains(.withoutEscapingSlashes))
		}
		
		public static func escape<StringType>(_ string: StringType, escapingSlashes: Bool = true) -> String where StringType: StringProtocol {
			var escaped = String(Const.quoteChar)
			escaped.reserveCapacity(Int(Float(string.count) * 1.2))
			for ch in string {
				switch ch {
				case "\"":      escaped += "\\\""
				case "\\":      escaped += "\\\\"
				case "/":
					if escapingSlashes {
						escaped += "\\/"
					} else {
						escaped.append(ch)
					}
				case "\u{08}":  escaped += "\\b"
				case "\u{09}":  escaped += "\\t"
				case "\u{0A}":  escaped += "\\n"
				case "\u{0C}":  escaped += "\\f"
				case "\u{0D}":  escaped += "\\r"
				default:        escaped.append(ch)
				}
			}
			escaped.append(Const.quoteChar)
			return escaped
		}

		@inline(__always)
		private var prettyPrint: Bool {
			options.contains(.prettyPrinted)
		}
	}

	enum Const {
		static let null: StaticString = "null"
		static let `true`: StaticString = "true"
		static let `false`: StaticString = "false"
		static let bracketSquareL: StaticString = "["
		static let bracketSquareR: StaticString = "]"
		static let bracketCurlyL: StaticString = "{"
		static let bracketCurlyR: StaticString = "}"
		static let comma: StaticString = ","
		static let colon: StaticString = ":"
		static let space: StaticString = " "
		static let lf: StaticString = "\n"
		static let indent: StaticString = "  "
		
		static let quote: StaticString = "\""
		static let quoteChar: Character = "\""
		
		static func indent(count: UInt) -> String {
			.init(repeating: Const.indent.description, count: Int(count))
		}
	}
}

extension JSON: Equatable {
}

extension JSON: ExpressibleByNilLiteral {
	public init(nilLiteral: ()) {
		self = .null
	}
}

extension JSON: ExpressibleByStringLiteral {
	public init(stringLiteral value: StringLiteralType) {
		self = .string(value)
	}
}

extension JSON: ExpressibleByBooleanLiteral {
	public init(booleanLiteral value: BooleanLiteralType) {
		self = .bool(value)
	}
}

extension JSON: ExpressibleByIntegerLiteral {
	public init(integerLiteral value: IntegerLiteralType) {
		self = .number(value < 0
					   ? .init(Int64(value))
					   : .init(UInt64(value)))
	}
}

extension JSON: ExpressibleByFloatLiteral {
	public init(floatLiteral value: FloatLiteralType) {
		self = .number(Double(value))
	}
}

extension JSON: ExpressibleByArrayLiteral {
	public typealias ArrayLiteralElement = JSON
	
	public init(arrayLiteral elements: Value...) {
		self = .array(elements)
	}
}

extension JSON: ExpressibleByDictionaryLiteral {
	public typealias Key = String
	public typealias Value = JSON
	
	public init(dictionaryLiteral elements: (String, Value)...) {
		self = .object([String : Value](elements) { l, r in r })
	}
}

extension JSON: CustomStringConvertible {
	public var description: String {
		Encoder().encode(self)
	}
}

extension JSON: Codable {
	private struct CodingKeys: CodingKey {
		var stringValue: String
		var intValue: Int?

		init(stringValue: String) {
			self.stringValue = stringValue
		}

		init(intValue: Int) {
			self.intValue = intValue
			self.stringValue = ""
		}
	}
	
	public init(from decoder: Swift.Decoder) throws {
		let container = try decoder.singleValueContainer()
		if let v = try? container.decode(Bool.self) {
			self = .bool(v)
		} else if let v = try? container.decode(Int64.self) {
			self = .number(v)
		} else if let v = try? container.decode(Double.self) {
			self = .number(v)
		} else if let v = try? container.decode(String.self) {
			self = .string(v)
		} else if let v = try? container.decode([String: JSON].self) {
			self = .object(v)
		} else if let v = try? container.decode([JSON].self) {
			self = .array(v)
		} else {
			self = .null
		}
	}
	
	public func encode(to encoder: Swift.Encoder) throws {
		switch self {
		case .null:
			var container = encoder.singleValueContainer()
			try container.encodeNil()
		case .number(let v):
			var container = encoder.singleValueContainer()
			try container.encode(v)
		case .bool(let v):
			var container = encoder.singleValueContainer()
			try container.encode(v)
		case .string(let v):
			var container = encoder.singleValueContainer()
			try container.encode(v)
		case .array(let v):
			var container = encoder.singleValueContainer()
			try container.encode(v)
		case .object(let v):
			var container = encoder.container(keyedBy: CodingKeys.self)
			for (key, value) in v {
				try container.encode(value, forKey: CodingKeys(stringValue: key))
			}
		}
	}
}
