import NIOHTTP1
import Vapor

/// Configuration used for populating headers in response for CORS requests.
public struct CORSOptions: Sendable {
	public typealias AllowOriginSetting = CORSMiddleware.AllowOriginSetting

	public static let defaultAllowedMethods: [HTTPMethod] = [
		.GET, .POST, .PUT, .HEAD, .DELETE, .PATCH,
	]

	public static let defaultAllowedHeaders: [HTTPHeaders.Name] = [
		.accept, .authorization, .contentType, .origin, .xRequestedWith,
	]

	public static let defaultCacheExpiration = 3600

	/// Setting that controls which origin values are allowed.
	public var allowedOrigin: CORSMiddleware.AllowOriginSetting

	/// Header string containing methods that are allowed for a CORS request response.
	public var allowedMethods: [HTTPMethod]

	/// Header string containing headers that are allowed in a response for CORS request.
	public var allowedHeaders: [HTTPHeaders.Name]

	/// If set to yes, cookies and other credentials will be sent in the response for CORS request.
	public var allowCredentials: Bool

	/// Optionally sets expiration of the cached pre-flight request. Value is in seconds.
	public var cacheExpiration: Int?

	/// Headers exposed in the response of pre-flight request.
	public var exposedHeaders: [HTTPHeaders.Name]?

	/// Instantiate a CORSConfiguration struct that can be used to create a `CORSConfiguration`
	/// middleware for adding support for CORS in your responses.
	///
	/// - parameters:
	///   - allowedOrigin: Setting that controls which origin values are allowed.
	///   - allowedMethods: Methods that are allowed for a CORS request response.
	///   - allowedHeaders: Headers that are allowed in a response for CORS request.
	///   - allowCredentials: If cookies and other credentials will be sent in the response.
	///   - cacheExpiration: Optionally sets expiration of the cached pre-flight request in seconds.
	///   - exposedHeaders: Headers exposed in the response of pre-flight request.
	public init(
		allowedOrigin: AllowOriginSetting = .originBased,
		allowedMethods: [HTTPMethod] = defaultAllowedMethods,
		allowedHeaders: [HTTPHeaders.Name] = defaultAllowedHeaders,
		allowCredentials: Bool = true,
		cacheExpiration: Int? = defaultCacheExpiration,
		exposedHeaders: [HTTPHeaders.Name]? = nil
	) {
		self.allowedOrigin = allowedOrigin
		self.allowedMethods = allowedMethods
		self.allowedHeaders = allowedHeaders
		self.allowCredentials = allowCredentials
		self.cacheExpiration = cacheExpiration
		self.exposedHeaders = exposedHeaders
	}
	
	public init(from encoded: [String: JSON]) {
		allowedOrigin = Self.decodeAllowOriginSetting(from: encoded[Keys.allowed_origin])
		allowedMethods = Self.decode(methods: encoded[Keys.allowed_methods])
			?? Self.defaultAllowedMethods
		var headers = Self.decode(headers: encoded[Keys.allowed_headers])
			?? Self.defaultAllowedHeaders
		if let extra = Self.decode(headers: encoded[Keys.extra_allowed_headers]) {
			headers += extra
		}
		allowedHeaders = headers
		allowCredentials = encoded[Keys.allow_credentials]?.boolValue
			?? true
		cacheExpiration = encoded[Keys.cache_expiration]?.valueAsInt64.map(Int.init)
			?? Self.defaultCacheExpiration
		exposedHeaders = Self.decode(headers: encoded[Keys.exposed_headers])
	}
	
	public var encoded: [String: any Encodable] {
		var encoded: [String: any Encodable] = [
			Keys.allowed_origin: Self.encode(allowedOrigin),
			Keys.allowed_methods: Self.encode(methods: allowedMethods),
			Keys.allowed_headers: Self.encode(headers: allowedHeaders),
			Keys.allow_credentials: allowCredentials,
		]
		if let cacheExpiration = cacheExpiration {
			encoded[Keys.cache_expiration] = cacheExpiration
		}
		if let exposedHeaders = exposedHeaders {
			encoded[Keys.exposed_headers] = Self.encode(headers: exposedHeaders)
		}
		return encoded
	}

	public var configuration: CORSMiddleware.Configuration {
		.init(allowedOrigin: allowedOrigin, allowedMethods: allowedMethods, allowedHeaders: allowedHeaders, allowCredentials: allowCredentials, cacheExpiration: cacheExpiration, exposedHeaders: exposedHeaders)
	}

	public static func decodeAllowOriginSetting(from: JSON?) -> AllowOriginSetting {
		switch from {
		case nil:					return .originBased
		case .string(let str):
			switch str {
			case "origin_based":	return .originBased
			case "all", "*":		return .all
			case "none":			return .none
			default:				return .custom(str)
			}
		case .array(let vs):
			return .any(.init(vs.compactMap(\.stringValue)))
		default:
			return .none
		}
	}
	
	public static func encode(_ settings: AllowOriginSetting) -> any Encodable {
		switch settings {
		case .originBased:			return "origin_based"
		case .none:					return "none"
		case .all:					return "all"
		case .any(let vs):			return [String](vs)
		case .custom(let v):		return v
		}
	}

	private static func decode(headers: JSON?) -> [HTTPHeaders.Name]? {
		switch headers {
		case .string(let v):
			return v.split(separator: ",").map(Self.decode(header:))
		case .array(let vs):
			return vs.compactMap(\.stringValue).map(Self.decode(header:))
		default:
			return nil
		}
	}

	private static func decode<T>(header: T) -> HTTPHeaders.Name
	where T: StringProtocol {
		.init(header.trimmingCharacters(in: .whitespaces).uppercased())
	}

	private static func decode(methods: JSON?) -> [HTTPMethod]? {
		switch methods {
		case .string(let v):
			return v.split(separator: ",").map(Self.decode(method:))
		case .array(let vs):
			return vs.compactMap(\.stringValue).map(Self.decode(method:))
		default:
			return nil
		}
	}

	private static func decode<T>(method: T) -> HTTPMethod
	where T: StringProtocol {
		.init(rawValue: method.trimmingCharacters(in: .whitespaces).uppercased())
	}

	private static func encode(methods: [HTTPMethod]) -> String {
		methods.map({ "\($0)" }).joined(separator: ", ")
	}

	private static func encode(headers: [HTTPHeaders.Name]) -> String {
		headers.map({ String(describing: $0) }).joined(separator: ", ")
	}
}
