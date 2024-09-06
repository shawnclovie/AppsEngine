import Foundation

extension Keys {
	public static let RUNTIME_VERBOSE = "RUNTIME_VERBOSE"
}

extension HTTP.Header {
	public static let x_debug_ignore_body_process = "x-debug-ignore-body-process"
	public static let x_debug_host = "x-debug-host"
	public static let x_env = "x-env"
}

extension DebugFeatures {
	/// - Format: `Array<String>`
	public static let appConfig_includesAppIDs = Self(rawValue: "appConfig_includesAppIDs")
	/// - Format: any non-nil
	public static let engine_extractDebugHost = Self(rawValue: "engine_extractDebugHost")
	/// - Format: any non-nil
	public static let engine_ignoreBodyProcess = Self(rawValue: "engine_ignoreBodyProcess")
}

extension Errors {
	public static let api_rate_limit = Errors("api_rate_limit", .tooManyRequests)
	public static let forbidden = Errors("forbidden", .forbidden)
	public static let `internal` = Errors("internal", .internalServerError)
	public static let invalid_parameter = Errors("invalid_parameter", .badRequest)
	public static let timeout = Errors("timeout", .requestTimeout)
	public static let not_modified = Errors("not_modified", .notModified)
	public static let not_found = Errors("not_found", .notFound)
	public static let bad_request = Errors("bad_request", .badRequest)
	public static let unauthorized = Errors("unauthorized", .unauthorized)

	public static let invalid_app_config = Errors("invalid_app_config", .expectationFailed)
	public static let invalid_engine_config = Errors("invalid_engine_config", .internalServerError)
	public static let app_not_found = Errors("app_not_found", .badRequest)
	public static let environment_not_found = Errors("environment_not_found", .badRequest)
	public static let route_not_found = Errors("route_not_found", .badRequest)

	public static let database = Errors("database", .internalServerError)
	public static let database_constraint_violation = Errors("db_constraint_violation", .badRequest)
	public static let cache = Errors("cache", .internalServerError)
	public static let oss_unavailable = Errors("oss_unavailable", .internalServerError)
}
