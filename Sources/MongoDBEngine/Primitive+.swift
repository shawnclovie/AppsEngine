//
//  Primitive+.swift
//  
//
//  Created by Shawn Clovie on 15/8/2022.
//

import Foundation
import AppsEngine
import MongoCore


extension OptionalRange: PrimitiveConvertible
where Bound: LosslessStringConvertible {
	public func makePrimitive() -> Primitive? {
		description
	}
}

extension OptionalRange: Primitive
where Bound: Primitive & LosslessStringConvertible {}

extension Time: PrimitiveConvertible {
	public static func from(primitive: Primitive?) -> Self? {
		if let date = primitive as? Date {
			return Self(date)
		}
		if let ms = primitive.flatMap(anyToInt64) {
			return Self(unixMilli: ms)
		} else if let layout = primitive as? String {
			return Self(parse: layout)
		}
		return nil
	}
	
	public func makePrimitive() -> Primitive? {
		asDate
	}
}

extension JSON: Primitive {
	public static func from(primitive: Primitive?) -> JSON {
		switch primitive {
		case let v as Bool:
			return .bool(v)
		case let v as Double:
			return .number(v)
		case let v as String:
			return .string(v)
		case let doc as Document:
			if doc.isArray {
				var vs: [JSON] = []
				vs.reserveCapacity(doc.count)
				for v in doc.values {
					vs.append(.from(primitive: v))
				}
				return .array(vs)
			} else {
				var vs: [String: JSON] = [:]
				vs.reserveCapacity(doc.count)
				for pair in doc.pairs {
					vs[pair.key] = .from(primitive: pair.value)
				}
				return .object(vs)
			}
		default:
			return .null
		}
	}

	public func makePrimitive() -> Primitive? {
		primitiveValue
	}
	
	var primitiveValue: Primitive {
		switch self {
		case .null:
			return Null()
		case .number(let v):
			return (v as NSDecimalNumber).doubleValue
		case .string(let v):
			return v
		case .bool(let v):
			return v
		case .array(let vs):
			var doc = Document(isArray: true)
			for v in vs {
				doc.append(v.primitiveValue)
			}
			return doc
		case .object(let v):
			var doc = Document()
			for (k, v) in v {
				doc[k] = v.primitiveValue
			}
			return doc
		}
	}
}

extension BSON.Document: JSONEncodable {
	public var jsonValue: JSON {
		if isArray {
			return .array(values.map(JSON.from(primitive:)))
		}
		var vs: [String: JSON] = [:]
		vs.reserveCapacity(count)
		for pair in pairs {
			vs[pair.key] = .from(primitive: pair.value)
		}
		return .object(vs)
	}
}
