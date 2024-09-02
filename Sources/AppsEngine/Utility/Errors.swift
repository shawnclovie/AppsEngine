import Atomics
import Foundation
import NIOHTTP1

public protocol WrapErrorDescribable {
	func description(withCaller: Bool, useReflect: Bool) -> String
	func jsonValue(withCaller: Bool, useReflect: Bool) -> JSON
}

public struct AnyError<Object: Encodable & Sendable>
: Error, Sendable, Encodable,
  CustomStringConvertible, CustomDebugStringConvertible,
  WrapErrorDescribable {
	public let object: Object
	public let debugObject: (any Encodable & Sendable)?
	public let wrapped: Error?
	
	public init(_ obj: Object,
				debug: (any Encodable & Sendable)? = nil,
				wrap: Error? = nil) {
		object = obj
		self.debugObject = debug
		wrapped = wrap
	}
	
	public func encode(to encoder: Encoder) throws {
		var container = encoder.singleValueContainer()
		try container.encode(description)
	}
	
	public func description(withCaller: Bool, useReflect: Bool) -> String {
		var desc = "\(object)"
		if useReflect, let debugObject {
			desc.append(":")
			desc.append(extractDescription(debugObject, withCaller: withCaller, useReflect: useReflect))
		}
		if let wrapped {
			desc.append("(")
			desc.append(extractDescription(wrapped, withCaller: withCaller, useReflect: useReflect))
			desc.append(")")
		}
		return desc
	}

	public var description: String {
		description(withCaller: false, useReflect: false)
	}

	public var debugDescription: String {
		description(withCaller: true, useReflect: true)
	}

	public func jsonValue(withCaller: Bool, useReflect: Bool) -> JSON {
		var desc: [String: JSON] = [
			Keys.description: .string(extractDescription(object, withCaller: withCaller, useReflect: useReflect)),
		]
		if useReflect, let debugObject {
			desc[Keys.debug] = .string(extractDescription(debugObject, withCaller: withCaller, useReflect: useReflect))
		}
		if let wrapped {
			desc[Keys.wrapped] = .string(extractDescription(wrapped, withCaller: withCaller, useReflect: useReflect))
		}
		return .object(desc)
	}
}

public protocol WrappableError: Error, CustomStringConvertible, Encodable {
	/// Get base type
	var base: Errors {get}
	/// Make new error with new type and other original error info
	func rebase(_ base: Errors) -> Self
	/// Get original error
	func unwrap() -> Error?
	
	func collectExtra() -> Errors.Extra
	
	var jsonValue: JSON { get }
}

extension WrappableError {
	public func convertOrWrap(_ err: Error, extra: Errors.Extra? = nil, callerSkip: UInt = 0) -> WrapError {
		if var err = err as? WrapError {
			if let extra {
				err.merge(extra: extra)
			}
			return err
		}
		if let err = err as? Errors {
			return WrapError(err, wrapped: nil, extra, callerSkip: 1 + callerSkip)
		}
		return WrapError(base, err, extra, callerSkip: 1 + callerSkip)
	}
}

public struct Errors: WrappableError, Equatable, Encodable, Hashable {
	public typealias Extra = [String: JSON]
		
	public let name: String
	public let status: HTTPResponseStatus
	
	public init(_ name: String, _ status: HTTPResponseStatus) {
		self.name = name
		self.status = status
	}
	
	public func encode(to encoder: Encoder) throws {
		var container = encoder.singleValueContainer()
		try container.encode(description)
	}
	
	public var jsonValue: JSON {
		[Keys.name: .string(name)]
	}
	
	public func hash(into hasher: inout Hasher) {
		hasher.combine(name)
		hasher.combine(status.code)
	}

	public var description: String { name }

	public var localizedDescription: String { description }

	public var base: Errors { self }

	public func rebase(_ base: Errors) -> Self { base }

	public func unwrap() -> Error? { nil }
	
	public func collectExtra() -> Errors.Extra { .init() }
}

public struct WrapError: WrappableError, CustomDebugStringConvertible {
	public static let shouldCaptureCaller = ManagedAtomic(false)

	public private(set) var base: Errors
	public let original: Error?
	public let wrapped: Error?
	public private(set) var extra: Errors.Extra?
	public let caller: String?

	public init(_ base: Errors,
				wrapped: Error? = nil,
				_ extra: Errors.Extra? = nil,
				callerSkip: UInt = 0,
				maxStack: UInt = 1) {
		self.base = base
		self.original = nil
		self.wrapped = wrapped
		self.extra = extra
		caller = Self.shouldCaptureCaller.load(ordering: .sequentiallyConsistent)
		? CallerStack.capture(skip: 1 + callerSkip, max: maxStack).description
		: nil
	}

	public init(_ base: Errors,
				_ original: String,
				wrapped: Error? = nil,
				_ extra: Errors.Extra? = nil,
				callerSkip: UInt = 0,
				maxStack: UInt = 1) {
		self.base = base
		self.original = AnyError(original)
		self.wrapped = wrapped
		self.extra = extra
		caller = Self.shouldCaptureCaller.load(ordering: .sequentiallyConsistent)
		? CallerStack.capture(skip: 1 + callerSkip, max: maxStack).description
		: nil
	}

	public init(_ base: Errors,
				_ original: Error? = nil,
				wrapped: Error? = nil,
				_ extra: Errors.Extra? = nil,
				callerSkip: UInt = 0,
				maxStack: UInt = 1) {
		self.base = base
		self.original = original
		self.wrapped = wrapped
		self.extra = extra
		caller = Self.shouldCaptureCaller.load(ordering: .sequentiallyConsistent)
		? CallerStack.capture(skip: 1 + callerSkip, max: maxStack).description
		: nil
	}

	public subscript(key: String) -> JSON {
		get { extra?[key] ?? .null }
		set {
			if extra == nil {
				extra = [key: newValue]
			} else {
				extra?[key] = newValue
			}
		}
	}

	fileprivate mutating func merge(extra: Errors.Extra) {
		if var ownExtra = self.extra, !ownExtra.isEmpty {
			for (key, value) in extra {
				ownExtra[key] = value
			}
			self.extra = ownExtra
		} else {
			self.extra = extra
		}
	}

	public func rebase(_ base: Errors) -> Self {
		var dup = self
		dup.base = base
		return dup
	}
	
	public func wrap(_ error: Error, extra: Errors.Extra? = nil,
					 callerSkip: UInt = 0, maxStack: UInt = 1) -> WrapError {
		WrapError(detectBase(error), error, wrapped: self, extra,
				  callerSkip: 1 + callerSkip, maxStack: maxStack)
	}
	
	public func wrap<Description: Encodable & Sendable>(
		_ errorDesc: Description,
		extra: Errors.Extra? = nil,
		callerSkip: UInt = 0,
		maxStack: UInt = 1
	) -> WrapError {
		WrapError(base, AnyError(errorDesc), wrapped: self, extra,
				  callerSkip: 1 + callerSkip, maxStack: maxStack)
	}
	
	public func unwrap() -> Error? { original }
	
	public func collectExtra() -> Errors.Extra {
		Self.collectExtra(self)
	}
	
	public func description(withCaller: Bool, useReflect: Bool) -> String {
		append(base: base.name, withCaller: withCaller, useReflect: useReflect)
	}
	
	public var description: String {
		append(base: base.name, withCaller: false, useReflect: false)
	}

	public var debugDescription: String {
		append(base: base.name, withCaller: true, useReflect: true)
	}

	public var localizedDescription: String { description }
	
	public func contains(oneOf errs: Errors...) -> Bool {
		contains(oneOf: Set(errs))
	}
	
	public func contains(oneOf errs: Set<Errors>) -> Bool {
		if errs.contains(base) {
			return true
		}
		if let err = original as? WrappableError, errs.contains(err.base) {
			return true
		}
		if let err = wrapped as? WrappableError, errs.contains(err.base) {
			return true
		}
		return false
	}
	
	public var jsonValue: JSON {
		jsonValue(withCaller: false, useReflect: false)
	}

	public func jsonValue(withCaller: Bool, useReflect: Bool) -> JSON {
		var err = [Keys.name: JSON.string(base.name)]
		if let original = original {
			err[Keys.original] = extractStructuredError(original, withCaller: withCaller, useReflect: useReflect)
		}
		if let wrapped = wrapped {
			err[Keys.wrapped] = extractStructuredError(wrapped, withCaller: withCaller, useReflect: useReflect)
		}
		if withCaller, let caller {
			err[Keys.caller] = .string(caller)
		}
		if let extra = extra {
			err[Keys.extra] = .object(extra)
		}
		return .object(err)
	}

	private func detectBase(_ err: Error) -> Errors {
		switch err {
		case let e as WrapError:
			return e.base
		case let e as Errors:
			return e
		default:
			return base
		}
	}
	
	private func append(base: String = "", withCaller: Bool, useReflect: Bool) -> String {
		var bracketedDetail = ""
		if let original = original {
			bracketedDetail.append(extractDescription(original, withCaller: withCaller, useReflect: useReflect))
		}
		if withCaller, let caller {
			bracketedDetail.append(" @\(caller)")
		}
		if let extra {
			for (key, value) in extra {
				if !bracketedDetail.isEmpty {
					bracketedDetail.append(",")
				}
				bracketedDetail.append("\(key)=\(value)")
			}
		}
		var str = base
		if !bracketedDetail.isEmpty {
			str.append("(")
			str.append(bracketedDetail)
			str.append(")")
		}
		if let wrapped = wrapped {
			str.append(withCaller ? ")\n:" : ":")
			if let be = wrapped as? WrapError {
				str.append(be.append(withCaller: withCaller, useReflect: useReflect))
			} else {
				str.append(extractDescription(wrapped, withCaller: withCaller, useReflect: useReflect))
			}
		}
		return str
	}

	private static func collectExtra(_ err: Error) -> Errors.Extra {
		guard let e = err as? WrapError else {
			return .init()
		}
		var extra = e.extra ?? [:]
		if let it = e.original {
			for (key, value) in collectExtra(it) {
				extra[key] = value
			}
		}
		if let it = e.wrapped {
			for (key, value) in collectExtra(it) {
				extra[key] = value
			}
		}
		return extra
	}
}

extension WrapError: Encodable {
	public func encode(to encoder: Encoder) throws {
		var container = encoder.singleValueContainer()
		try container.encode(description)
	}
}

private func extractDescription(_ err: Any, withCaller: Bool, useReflect: Bool) -> String {
	switch err {
	case let e as WrapError:
		return e.description(withCaller: withCaller, useReflect: useReflect)
	case let e as WrapErrorDescribable:
		return e.description(withCaller: withCaller, useReflect: useReflect)
	case let e as Errors:
		return e.description
	case let e as LocalizedError:
		return e.errorDescription ?? "\(e)"
	case let s as String:
		return s
	default:
		return useReflect ? String(reflecting: err) : "\(err)"
	}
}

private func extractStructuredError(_ err: Any, withCaller: Bool, useReflect: Bool) -> JSON {
	switch err {
	case let e as WrapError:
		return e.jsonValue(withCaller: withCaller, useReflect: useReflect)
	case let e as WrapErrorDescribable:
		return e.jsonValue(withCaller: withCaller, useReflect: useReflect)
	case let e as Errors:
		return e.jsonValue
	case let e as LocalizedError:
		return .string(e.errorDescription ?? "\(e)")
	case let s as String:
		return .string(s)
	default:
		return .string(useReflect ? String(reflecting: err) : "\(err)")
	}
}
