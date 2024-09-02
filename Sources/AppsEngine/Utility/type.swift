import Foundation

public func isNumeric(_ v: Any?) -> Bool {
	switch v {
	case is Int64:		fallthrough
	case is Int:		fallthrough
	case is Int8:		fallthrough
	case is Int16:		fallthrough
	case is Int32:		fallthrough
	case is UInt:		fallthrough
	case is UInt8:		fallthrough
	case is UInt16:		fallthrough
	case is UInt32:		fallthrough
	case is UInt64:		fallthrough
	case is NSNumber:	fallthrough
	case is Decimal:	fallthrough
	case is Double:		fallthrough
	case is Float:
		return true
	default:
		return false
	}
}

extension Int64 {
	public static func from(_ v: Any) -> Self? {
		anyToInt64(v)
	}
}

/// Try to convert basic type to `Int64`.
///
/// Return by parameter's type:
///   - `String`|`Substring` or numeric: `Int64.init`.
///   - `Bool`: `true` -> `1`, `false` -> `0`.
///   - other: `nil`
public func anyToInt64(_ v: Any) -> Int64? {
	switch v {
	case let v as Int64:		return v
	case let v as Int:			return Int64(v)
	case let v as Int8:			return Int64(v)
	case let v as Int16:		return Int64(v)
	case let v as Int32:		return Int64(v)
	case let v as UInt:
		return v >= UInt(Int64.max) ? nil : Int64(v)
	case let v as UInt8:		return Int64(v)
	case let v as UInt16:		return Int64(v)
	case let v as UInt32:		return Int64(v)
	case let v as UInt64:
		return v >= UInt64(Int64.max) ? nil : Int64(v)
	case let v as Double:
		return v >= Double(Int64.max) || v <= Double(Int64.min) ? nil : Int64(v)
	case let v as Float:
		return v >= Float(Int64.max) || v <= Float(Int64.min) ? nil : Int64(v)
	case let v as CGFloat:
		return v >= CGFloat(Int64.max) || v <= CGFloat(Int64.min) ? nil : Int64(v)
	case let v as NSDecimalNumber:
		let d = v as Decimal
		return d >= Decimal(Int64.max) || d <= Decimal(Int64.min) ? nil : v.int64Value
	case let v as NSNumber:
		return v.int64Value
	case let v as Decimal:
		return v >= Decimal(Int64.max) || v <= Decimal(Int64.min) ? nil : NSDecimalNumber(decimal: v).int64Value
	case let v as Bool:			return v ? 1 : 0
	case let v as String:		return Int64(v)
	case let v as Substring:	return Int64(v)
	case let v as JSON:			return v.valueAsInt64
	default:return nil
	}
}

public func anyToUInt64(_ v: Any) -> UInt64? {
	switch v {
	case let v as UInt:			return UInt64(v)
	case let v as UInt8:		return UInt64(v)
	case let v as UInt16:		return UInt64(v)
	case let v as UInt32:		return UInt64(v)
	case let v as UInt64:		return v
	case let v as Int64:		return v < 0 ? nil : UInt64(v)
	case let v as Int:			return v < 0 ? nil : UInt64(v)
	case let v as Int8:			return v < 0 ? nil : UInt64(v)
	case let v as Int16:		return v < 0 ? nil : UInt64(v)
	case let v as Int32:		return v < 0 ? nil : UInt64(v)
	case let v as Double:
		return v < 0 || v >= Double(UInt64.max) ? nil : UInt64(v)
	case let v as Float:
		return v < 0 || v >= Float(UInt64.max) ? nil : UInt64(v)
	case let v as CGFloat:
		return v < 0 || v >= CGFloat(UInt64.max) ? nil : UInt64(v)
	case let v as NSDecimalNumber:
		let d = v as Decimal
		return d >= Decimal(Int64.max) || d < Decimal(0) ? nil : v.uint64Value
	case let v as NSNumber:		return v.uint64Value
	case let v as Decimal:		return NSDecimalNumber(decimal: v).uint64Value
	case let v as Bool:			return v ? 1 : 0
	case let v as String:		return UInt64(v)
	case let v as Substring:	return UInt64(v)
	case let v as JSON:			return v.valueAsUInt64
	default:return nil
	}
}

/// Try to convert basic type to `Double`.
public func anyToDouble(_ v: Any) -> Double? {
	switch v {
	case let v as Double:		return v
	case let v as Float:		return Double(v)
	case let v as CGFloat:		return Double(v)
	case let v as Int64:		return Double(v)
	case let v as Int:			return Double(v)
	case let v as Int8:			return Double(v)
	case let v as Int16:		return Double(v)
	case let v as Int32:		return Double(v)
	case let v as UInt:			return Double(v)
	case let v as UInt8:		return Double(v)
	case let v as UInt16:		return Double(v)
	case let v as UInt32:		return Double(v)
	case let v as UInt64:		return Double(v)
	case let v as NSNumber:		return v.doubleValue
	case let v as Decimal:		return NSDecimalNumber(decimal: v).doubleValue
	case let v as Bool:			return v ? 1 : 0
	case let v as String:		return Double(v)
	case let v as Substring:	return Double(v)
	case let v as JSON:			return v.valueAsDouble
	default:return nil
	}
}

/// Try to convert basic type to `Bool`.
///
/// Return by parameter's type:
///   - `String`|`Substring`: with `stringToBool`.
///   - numeric: non-zero as true.
///   - `Bool`: itself.
///   - other: `nil`
public func anyToBool(_ v: Any) -> Bool? {
	switch v {
	case let v as String:
		return stringToBool(v)
	case let v as Substring:
		return stringToBool(v)
	case let v as Int64:		return v != 0
	case let v as Int:			return v != 0
	case let v as Int8:			return v != 0
	case let v as Int16:		return v != 0
	case let v as Int32:		return v != 0
	case let v as UInt:			return v != 0
	case let v as UInt8:		return v != 0
	case let v as UInt16:		return v != 0
	case let v as UInt32:		return v != 0
	case let v as UInt64:		return v != 0
	case let v as Double:		return v != 0
	case let v as Float:		return v != 0
	case let v as CGFloat:		return v != 0
	case let v as NSNumber:		return v.boolValue
	case let v as Decimal:		return NSDecimalNumber(decimal: v).boolValue
	case let v as Bool:			return v
	case let v as JSON:			return v.boolValue
	default:return nil
	}
}

/// Parse string to bool.
/// - Returns: `true` if first character of `v` is in `["t", "T", "y", "Y", "1"]`.
public func stringToBool<Argument: StringProtocol>(_ v: Argument) -> Bool {
	guard let ch = v.first else { return false }
	return ["t", "T", "y", "Y", "1"].contains(ch)
}
