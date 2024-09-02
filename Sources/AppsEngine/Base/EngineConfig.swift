import Fluent
import Vapor
import Yams

public actor EngineConfig: Sendable {
	public static let defaultLocalAppDirectory = "apps"

	public nonisolated let workingDirectory: URL

	public nonisolated let name: String

	public nonisolated let debugFeatures: [String: JSON]?

	public let server: APIServer

	public nonisolated let timezone: TimeZone

	public let appSource: AppSource

	let resource: Resource.Config?

	public nonisolated let rawData: JSON

	public nonisolated let defaultLogger: Logger
	public nonisolated let startupLogger: Logger

	let loggers: [String: Logger]

	let metric: Metric?

	public var snowflakeNode = Snowflake.Node(node: 0)

	public nonisolated let verboseItems: Set<String>

	public init(
		workingDirectory: URL,
		content: Data,
		format: Format,
		localAppDirectory: URL? = nil
	) async throws {
		let decoded: JSON
		do {
			decoded = switch format {
			case .json:
				try JSON.Decoder().decode(content)
			case .yaml:
				JSON(from: try Yams.load(yaml: String(decoding: content, as: UTF8.self)))
			}
		} catch {
			throw AnyError("\(Self.self).initialize: decode config(\(format)) failed", wrap: error)
		}
		guard case .object(_) = decoded else {
			throw AnyError("\(Self.self).initialize: content should be dictionary")
		}
		try await self.init(workingDirectory: workingDirectory, rawData: decoded, localAppDirectory: localAppDirectory)
	}

	public init(
		workingDirectory: URL,
		rawData: JSON,
		localAppDirectory: URL? = nil
	) async throws {
		let name = rawData[Keys.name].stringValue ?? "server"
		let server: APIServer
		do {
			server = try APIServer(rawData[Keys.server])
		} catch {
			throw AnyError("\(Self.self).initialize: 'server' failed", wrap: error)
		}
		let timezone: TimeZone
		if let v = rawData[Keys.timezone].stringValue {
			guard let tz = TimeZone(identifier: v) else {
				throw AnyError("\(Self.self).initialize: invalid timezone: '\(v)'")
			}
			timezone = tz
		} else {
			timezone = .gmt
		}
		let appSource = AppSource(
			localAppsPath: localAppDirectory ?? workingDirectory.appendingPathComponent(Self.defaultLocalAppDirectory),
			config: rawData["app_source"].objectValue)

		var loggers: [String: Logger] = [:]
		if let rawLoggers = rawData[Keys.logger].objectValue {
			for it in rawLoggers {
				guard let cfg = it.value.objectValue else { continue }
				let outputs = try await Self.parseLogOutputer(appName: name, config: cfg)
				loggers[it.key] = .init(outputers: outputs, timezone: timezone)
			}
		}
		var metric: Metric?
		if let raw = rawData[Keys.metric].objectValue {
			do {
				let host = raw[Keys.host]?.stringValue ?? "127.0.0.1"
				let port = raw[Keys.port]?.valueAsInt64 ?? 8125
				metric = try Metric(host: host, port: Int(port))
			} catch {
				throw AnyError("\(Self.self).initialize: metric setup failed", wrap: error)
			}
		}
		let resource: Resource.Config
		if let cfg = rawData["resources"].objectValue {
			resource = try .init(cfg)
		} else {
			throw AnyError("\(Self.self).initialize: resources should be dictionary")
		}
		self.init(workingDirectory: workingDirectory,
				  name: name,
				  debugFeatures: rawData["debug_features"].objectValue,
				  server: server,
				  timezone: timezone, appSource: appSource,
				  resource: resource, rawData: rawData,
				  loggers: loggers, metric: metric)
	}

	public init(
		workingDirectory: URL,
		name: String,
		debugFeatures: [String : JSON]?,
		server: APIServer,
		timezone: TimeZone,
		appSource: AppSource,
		resource: Resource.Config?,
		rawData: JSON = [:],
		loggers: [String : Logger],
		metric: Metric? = nil
	) {
		self.workingDirectory = workingDirectory
		self.name = name
		self.debugFeatures = debugFeatures
		self.server = server
		self.timezone = timezone
		self.appSource = appSource
		self.resource = resource
		self.rawData = rawData
		let def = loggers[Keys.default] ?? Logger()
		defaultLogger = def
		startupLogger = loggers["startup"] ?? def
		self.loggers = loggers

		let verbose = ProcessInfo.processInfo.environment
			.first(where: { key, _ in key.uppercased() == Keys.RUNTIME_VERBOSE })
		var verboseItems: [String] = []
		if let verbose = verbose?.value, !verbose.isEmpty {
			verboseItems.append(contentsOf: verbose.split(separator: ",").map({ $0.lowercased() }))
		}
		self.verboseItems = .init(verboseItems)
		if var metric {
			metric.verbose = verboseItems.contains("metric")
			self.metric = metric
		} else {
			self.metric = nil
		}
	}

	static func parseLogOutputer(appName: String, config: [String: JSON]) async throws -> [LogOutputer] {
		var outputers: [LogOutputer] = []
		for it in config {
			guard let vs = it.value.objectValue else {
				throw AnyError("'log.\(it.key)' should be map")
			}
			let level = Log.Level(rawValue: vs["level"]?.stringValue ?? "") ?? .info
			let output: LogOutputer
			switch it.key {
			case "console":
				output = LogConsoleOutputer(level: level, stream: .init(rawValue: vs["stream"]?.stringValue ?? "") ?? .stdout)
			// TODO: file logger
//			case "file":
//				output = parseFileLogger(name, format, level, vs)
			case "tcp":
				guard let port = vs[Keys.port]?.valueAsInt64, port > 0 else {
					throw AnyError("'log.\(it.key)'.port should > 0")
				}
				output = await LogTCPOutputer(
					level: level,
					options: .init(host: vs[Keys.host]?.stringValue ?? "127.0.0.1", port: Int(port)))
			default:
				throw AnyError("'log.\(it.key)' unknown output type")
			}
			outputers.append(output)
		}
		return outputers
	}

	func setSnowflake(node: Int64) {
		snowflakeNode = .init(node: node)
	}

	public nonisolated func isOn(_ feature: DebugFeatures) -> Bool {
		isDebugFeatureOn(feature.rawValue)
	}

	/// Check if debug feature on: was configured in any key of `debug_features`.
	/// - Parameter name: Feature name
	public nonisolated func isDebugFeatureOn(_ name: String? = nil) -> Bool {
		guard let debugFeatures else {
			return false
		}
		if let name, debugFeatures[name] != nil {
			return true
		}
		return debugFeatures[Keys.all] != nil
	}
	
	public nonisolated func debugFeature(_ feature: DebugFeatures) -> JSON? {
		debugFeature(feature.rawValue)
	}

	public nonisolated func debugFeature(_ name: String) -> JSON? {
		debugFeatures?[name]
	}
	
	public enum Format: String {
		case json, yaml
	}
	
	public struct APIServer: Sendable, CustomStringConvertible {
		public var host: String
		public var port: Int
		public var reuseAddress: Bool
		public var shutdownTimeout: TimeDuration
		/// Environment for Vapor
		public let environment: String?

		public init(
			host: String = "0.0.0.0",
			port: Int,
			reuseAddress: Bool = true,
			shutdownTimeout: TimeDuration = .seconds(3),
			environment: String? = nil
		) {
			self.host = host
			self.port = port
			self.reuseAddress = reuseAddress
			self.shutdownTimeout = shutdownTimeout
			self.environment = environment
		}

		public init(_ vs: JSON) throws {
			let shutdownTimeout: TimeDuration
			if let s = vs[Keys.shutdown_timeout].stringValue {
				do {
					shutdownTimeout = try TimeDuration.tryParse(s)
				} catch {
					throw AnyError("\(Keys.shutdown_timeout)'\(s)' invalid", wrap: error)
				}
			} else {
				shutdownTimeout = .seconds(3)
			}
			self.init(host: vs[Keys.host].stringValue ?? "0.0.0.0",
					  port: Int(vs[Keys.port].valueAsInt64 ?? 1080),
					  reuseAddress: vs[Keys.reuse_address].boolValue ?? true,
					  shutdownTimeout: shutdownTimeout,
					  environment: vs[Keys.environment].stringValue)
		}
		
		public var description: String {
			"host=\(host),port=\(port)"
		}
	}
	
	public struct AppSource : Sendable{
		public var localAppsPath: URL?
		public var pullInterval: TimeDuration
		public var path: String?
		public var config: [String: JSON]?

		public init(localAppsPath: URL? = nil,
					pullInterval: TimeDuration = .minutes(5),
					path: String? = nil,
					config: [String : JSON]? = nil) {
			self.localAppsPath = localAppsPath
			self.pullInterval = pullInterval
			self.path = path
			self.config = config
		}

		init(localAppsPath: URL?, config: [String : JSON]?) {
			self.localAppsPath = localAppsPath
			self.config = config
			path = config?[Keys.path]?.stringValue
			pullInterval = .parse(config?["pull_interval"]?.stringValue ?? "5m")
		}
	}

	public struct Zone: Sendable {
		public var name: String
		public var offset: Int
	}
}
