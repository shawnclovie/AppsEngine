//
//  JSONCodable.swift
//  
//
//  Created by Shawn Clovie on 14/9/2022.
//

import Foundation

public protocol JSONDecodable {
	init(from json: JSON) throws
}

public protocol JSONEncodable {
	var jsonValue: JSON { get }
}

public typealias JSONCodable = JSONEncodable & JSONDecodable

extension Bool: JSONEncodable {
	public var jsonValue: JSON {
		.bool(self)
	}
}

extension Int: JSONEncodable {
	public var jsonValue: JSON {
		.number(Int64(self))
	}
}

extension Int8: JSONEncodable {
	public var jsonValue: JSON {
		.number(Int64(self))
	}
}

extension Int16: JSONEncodable {
	public var jsonValue: JSON {
		.number(Int64(self))
	}
}

extension Int32: JSONEncodable {
	public var jsonValue: JSON {
		.number(Int64(self))
	}
}

extension Int64: JSONEncodable {
	public var jsonValue: JSON {
		.number(self)
	}
}

extension UInt: JSONEncodable {
	public var jsonValue: JSON {
		.number(UInt64(self))
	}
}

extension UInt8: JSONEncodable {
	public var jsonValue: JSON {
		.number(UInt64(self))
	}
}

extension UInt16: JSONEncodable {
	public var jsonValue: JSON {
		.number(UInt64(self))
	}
}

extension UInt32: JSONEncodable {
	public var jsonValue: JSON {
		.number(UInt64(self))
	}
}

extension UInt64: JSONEncodable {
	public var jsonValue: JSON {
		.number(self)
	}
}

extension Float32: JSONEncodable {
	public var jsonValue: JSON {
		.number(Double(self))
	}
}

extension Float64: JSONEncodable {
	public var jsonValue: JSON {
		.number(self)
	}
}

extension Decimal: JSONEncodable {
	public var jsonValue: JSON {
		.number(self)
	}
}

extension NSNumber: JSONEncodable {
	public var jsonValue: JSON {
		.number(self.decimalValue)
	}
}

extension String: JSONEncodable {
	public var jsonValue: JSON {
		.string(self)
	}
}

extension Substring: JSONEncodable {
	public var jsonValue: JSON {
		.string(.init(self))
	}
}

extension URL: JSONEncodable {
	public var jsonValue: JSON {
		.string(absoluteString)
	}
}

extension JSON: JSONEncodable {
	public var jsonValue: JSON {
		self
	}
}

extension [JSONEncodable]: JSONEncodable {
	public var jsonValue: JSON {
		.array(map({ $0.jsonValue }))
	}
}

extension [AnyHashable: JSONEncodable]: JSONEncodable {
	public var jsonValue: JSON {
		var obj: [String: JSON] = [:]
		obj.reserveCapacity(count)
		for (key, value) in self {
			obj[key.description] =  value.jsonValue
		}
		return .object(obj)
	}
}

extension [String: JSON] {
	public mutating func setValues(_ newValues: Self) {
		guard !newValues.isEmpty else {
			return
		}
		reserveCapacity(count + newValues.count)
		for (key, value) in newValues {
			self[key] = value
		}
	}
}
