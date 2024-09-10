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

	private let customData = TypedObjectHolder()

	/// Create config with arguments.
	///
	/// `rawData` would also be parsed and parsed config would cover arguments.
	public init(
		workingDirectory: URL,
		name: String? = nil,
		debugFeatures: [String : JSON]? = nil,
		server: APIServer? = nil,
		timezone: TimeZone? = nil,
		appSource: AppSource? = nil,
		localAppDirectory: URL? = nil,
		resource: Resource.Config? = nil,
		loggers: [String : Logger]? = nil,
		metric: Metric.Config? = nil,
		rawData: JSON = [:]
	) async throws {
		self.workingDirectory = workingDirectory
		self.name = rawData[Keys.name].stringValue ?? name ?? "server"
		do {
			if case .object(let vs) = rawData[Keys.server] {
				self.server = try APIServer(vs)
			} else if let server {
				self.server = server
			} else {
				throw AnyError("no server passed or defined")
			}
		} catch {
			throw AnyError("\(Self.self).initialize: 'server' failed", wrap: error)
		}
		if let v = rawData[Keys.timezone].stringValue {
			guard let tz = TimeZone(identifier: v) else {
				throw AnyError("\(Self.self).initialize: invalid timezone: '\(v)'")
			}
			self.timezone = tz
		} else if let timezone {
			self.timezone = timezone
		} else {
			self.timezone = .init(secondsFromGMT: 0)!
		}
		if case .object(let raw) = rawData["app_source"] {
			self.appSource = AppSource(
				localAppsPath: localAppDirectory ?? workingDirectory.appendingPathComponent(Self.defaultLocalAppDirectory),
				config: raw)
		} else {
			self.appSource = appSource ?? .init(
				localAppsPath: localAppDirectory ?? workingDirectory.appendingPathComponent(Self.defaultLocalAppDirectory),
				config: nil)
		}
		var loggers: [String: Logger] = loggers ?? [:]
		if case .object(let raw) = rawData[Keys.logger] {
			for it in raw {
				guard let cfg = it.value.objectValue else { continue }
				let outputs = try await Self.parseLogOutputer(appName: self.name, config: cfg)
				loggers[it.key] = .init(outputers: outputs, timezone: timezone)
			}
		}
		self.loggers = loggers
		if case .object(let cfg) = rawData["resources"] {
			self.resource = try .init(cfg)
		} else if let resource {
			self.resource = resource
		} else {
			throw AnyError("\(Self.self).initialize: resources should be dictionary")
		}

		self.debugFeatures = rawData["debug_features"].objectValue
		self.rawData = rawData

		let def = loggers[Keys.default] ?? Logger()
		defaultLogger = def
		startupLogger = loggers["startup"] ?? def

		let verbose = ProcessInfo.processInfo.environment
			.first(where: { key, _ in key.uppercased() == Keys.RUNTIME_VERBOSE })
		var verboseItems: [String] = []
		if let verbose = verbose?.value, !verbose.isEmpty {
			verboseItems.append(contentsOf: verbose.split(separator: ",").map({ $0.lowercased() }))
		}
		self.verboseItems = .init(verboseItems)
		var metricCFG: Metric.Config?
		if let raw = rawData[Keys.metric].objectValue {
			let host = raw[Keys.host]?.stringValue ?? "127.0.0.1"
			let port = raw[Keys.port]?.valueAsInt64 ?? 8125
			metricCFG = .init(host: host, port: Int(port))
		} else {
			metricCFG = metric
		}
		if let metricCFG {
			do {
				var metric = try Metric(host: metricCFG.host, port: metricCFG.port)
				metric.verbose = self.verboseItems.contains("metric")
				self.metric = metric
			} catch {
				throw AnyError("\(Self.self).initialize: metric setup failed", wrap: error)
			}
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

	/// Get custom data or parsed config.
	public func get<As: Sendable>(_ type: As.Type) async -> As? {
		await customData.get(type)
	}

	/// Set custom data or parsed config.
	public func set<As: Sendable>(_ value: As) async {
		await customData.set(value)
	}

	public enum Format: String {
		case json, yaml

		public func decode(_ data: Data) throws -> JSON {
			let decoded: JSON
			do {
				decoded = switch self {
				case .json:
					try JSON.Decoder().decode(data)
				case .yaml:
					JSON(from: try Yams.load(yaml: String(decoding: data, as: UTF8.self)))
				}
			} catch {
				throw AnyError("decode (\(self)) failed", wrap: error)
			}
			guard case .object(_) = decoded else {
				throw AnyError("data should be \(self) object")
			}
			return decoded
		}
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

		public init(_ vs: [String: JSON]) throws {
			let shutdownTimeout: TimeDuration
			if let s = vs[Keys.shutdown_timeout]?.stringValue {
				do {
					shutdownTimeout = try TimeDuration.tryParse(s)
				} catch {
					throw AnyError("\(Keys.shutdown_timeout)'\(s)' invalid", wrap: error)
				}
			} else {
				shutdownTimeout = .seconds(3)
			}
			self.init(host: vs[Keys.host]?.stringValue ?? "0.0.0.0",
					  port: Int(vs[Keys.port]?.valueAsInt64 ?? 1080),
					  reuseAddress: vs[Keys.reuse_address]?.boolValue ?? true,
					  shutdownTimeout: shutdownTimeout,
					  environment: vs[Keys.environment]?.stringValue)
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
