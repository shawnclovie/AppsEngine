import Foundation
import Vapor

public protocol Module: Sendable {
	var moduleName: String { get }

	var endpoints: [Endpoint] { get }

	var supportEnvironment: Bool { get }
	
	/// Resource did finish prepare, some module only resource may initial here.
	func resourceDidFinishPrepare(_ engine: Engine) async throws

	/// AppConfig is loading, some module only can parse here.
	/// It would be store in AppConfig, and then get.
	///
	/// e.g. `return .init(SomeConfig())` here
	///
	/// then get it with `ctx.context.config.get(SomeConfig.self)` in endpoint.
	func parseConfig(_ configSet: AppConfigSet,
					 environment: (name: String, raw: [String: JSON])?) async -> AppConfigParseResult?
}

public extension Module {
	var supportEnvironment: Bool { false }
	
	func resourceDidFinishPrepare(_ engine: Engine) async throws {}

	func parseConfig(_ configSet: AppConfigSet, environment: (name: String, raw: [String: JSON])?) async -> AppConfigParseResult? {
		nil
	}
}

public struct AppEnvRef: StorageKey, Encodable, Equatable, CustomStringConvertible, Sendable {
	public typealias Value = AppEnvRef
	
	public static func main(_ appID: String) -> Self {
		.init(appID, nil)
	}

	public var appID: String
	/// Environment name, `nil` means main one.
	///
	/// Storage:
	///   - PostgreSQL: `NULL` would cause UNIQUE INDEX issue, would store as empty string.
	public var env: String?
	
	public init(_ appID: String, _ env: String?) {
		self.appID = appID
		self.env = env
	}

	public var description: String {
		if let env {
			return "\(appID).\(env)"
		}
		return appID
	}
}

public struct AppConfigParseResult: Sendable {
	public var object: (any Sendable)?
	public var warnings: [String]

	public init(_ obj: (any Sendable)? = nil, warnings: [String] = []) {
		object = obj
		self.warnings = warnings
	}
}

public actor AppConfigSet: Sendable {
	public let core: AppConfig
	/// Raw environments config, keyed by environment name.
	public let rawEnvironments: [String: [String: JSON]]
	/// Loaded environments config by each modules, keyed by environment name.
	public private(set) var environments: [String: AppConfig] = [:]
	/// Warning infomation from loaded configuration.
	///
	/// format: `{environment: {module: warning_details}}`
	public private(set) var warnings: [String: [String: [String]]] = [:]

	public init(core: AppConfig, modules: [Module]) async {
		self.core = core
		var rawEnvironments: [String: [String: JSON]] = [:]
		switch core.raw[Keys.environments] {
		case .null:
			break
		case .array(let rawEnvs):
			for raw in rawEnvs {
				switch raw {
				case .string(let envName):
					rawEnvironments[envName] = [:]
				case .object(let vs):
					guard let envName = vs[Keys.name]?.stringValue else {
						continue
					}
					rawEnvironments[envName] = vs
				default:
					break
				}
			}
		case .object(let rawEnvs):
			for (envName, vs) in rawEnvs {
				rawEnvironments[envName] = vs.objectValue ?? [:]
			}
		default:
			warnings["(main)"] = [
				"environment": ["unknown format"],
			]
		}
		self.rawEnvironments = rawEnvironments

		if let warns = await parse(with: modules, for: core, environment: nil) {
			warnings["(main)"] = warns
		}
		if !rawEnvironments.isEmpty {
			let modsSupportEnv = modules.filter { $0.supportEnvironment }
			for (env, raw) in rawEnvironments {
				guard env != core.environment else {
					continue
				}
				let config = core.duplicate(environment: env)
				if let warns = await parse(with: modsSupportEnv, for: config, environment: (env, raw)) {
					warnings[env] = warns
				}
				environments[env] = config
			}
		}
	}

	private func parse(
		with mods: [Module],
		for config: AppConfig,
		environment: (name: String, raw: [String: JSON])?
	) async -> [String: [String]]? {
		var warnings: [String: [String]] = [:]
		for mod in mods {
			guard let res = await mod.parseConfig(self, environment: environment) else {
				continue
			}
			if !res.warnings.isEmpty {
				warnings[mod.moduleName] = res.warnings
			}
			if let v = res.object {
				await config.set(v)
			}
		}
		return warnings.isEmpty ? nil : warnings
	}

	func config(environment: String?) -> AppConfig? {
		environment.flatMap({ environments[$0] })
	}
}

public final class AppConfig: Sendable {
	public static let mainFile = "config.json"

	private actor CustomDataHolder {
		private var data: [ObjectIdentifier: any Sendable] = [:]

		public func get<As>(_ configType: As.Type) -> As? {
			data[ObjectIdentifier(configType)] as? As
		}

		public func set<As: Sendable>(_ value: As) {
			data[ObjectIdentifier(As.self)] = value
		}
	}

	public let appID: String
	public let appName: String?
	public let appGroup: String?
	public let hosts: [String: Host]
	public let timeOffset: Int?

	/// Environment name, `nil` for main environment.
	public let environment: String?

	public let cors: CORSOptions?
	public let encryptions: [String: AppEncryptConfig]

	public let raw: [String: JSON]
	private let customData = CustomDataHolder()

	public init(
		appID: String,
		appName: String?,
		appGroup: String? = nil,
		hosts: any Collection<Host>,
		timeOffset: Int? = nil,
		environment: String? = nil,
		cors: CORSOptions? = nil,
		encryptions: (any Collection<AppEncryptConfig>)? = nil,
		raw: [String: JSON] = [:]
	) {
		self.appID = appID
		self.appName = appName
		self.appGroup = appGroup
		var hostMap: [String: Host] = [:]
		for host in hosts {
			hostMap[host.host] = host
		}
		self.hosts = hostMap
		self.timeOffset = timeOffset
		self.environment = environment
		self.cors = cors
		var encryptionMap: [String: AppEncryptConfig] = [:]
		if let encryptions {
			for encryption in encryptions {
				encryptionMap[encryption.name] = encryption
			}
		}
		self.encryptions = encryptionMap
		self.raw = raw
	}

	convenience init(_ engineConfig: borrowing EngineConfig, rootPath: URL, environment: String?) throws {
		let raw: JSON
		do {
			let content = try Data(contentsOf: rootPath.appendingPathComponent(Self.mainFile))
			raw = try JSON.Decoder().decode(content)
		} catch {
			throw WrapError(.invalid_app_config, "config decoding failed")
		}
		guard let raw = raw.objectValue else {
			throw WrapError(.invalid_app_config, "config should be dictionary")
		}
		guard let appID = raw[Keys.app_id]?.stringValue else {
			throw WrapError(.invalid_app_config, "config should have \(Keys.app_id) on \(rootPath)")
		}
		var hosts: [Host] = []
		if let rawHosts = raw[Keys.hosts]?.arrayValue {
			for rawHost in rawHosts {
				switch rawHost {
				case .string(let v):
					hosts.append(.init(host: v, usage: .request, raw: nil))
				case .object(let vs):
					guard let host = Host(vs) else {
						break
					}
					hosts.append(host)
				default:
					break
				}
			}
		}
		var cors: CORSOptions?
		if let vs = raw[Keys.cors_options]?.objectValue,
		   vs[Keys.enabled]?.boolValue == true {
			cors = .init(from: vs)
		}
		var encryptions: [AppEncryptConfig] = []
		if let rawEncrypt = raw[Keys.encryptions]?.arrayValue {
			for vs in rawEncrypt {
				guard let id = vs[Keys.id].stringValue,
					  let secret = vs[Keys.secret].stringValue else {
					continue
				}
				let name = vs[Keys.name].stringValue ?? id
				encryptions.append(.init(name: name, id: id, secret: secret))
			}
		}
		self.init(appID: appID,
				  appName: raw[Keys.app_name]?.stringValue,
				  appGroup: raw[Keys.app_group]?.stringValue,
				  hosts: hosts,
				  timeOffset: raw[Keys.time_offset]?.valueAsInt64.map(Int.init),
				  environment: environment, cors: cors,
				  encryptions: encryptions, raw: raw)
	}

	func duplicate(environment: String) -> AppConfig {
		.init(appID: appID, appName: appName, appGroup: appGroup,
			  hosts: [], timeOffset: timeOffset,
			  environment: environment, cors: cors,
			  encryptions: encryptions.values,
			  raw: raw)
	}

	public var metricName: String {
		appName ?? appID
	}

	/// Get custom data or parsed config.
	public func get<As: Sendable>(_ type: As.Type) async -> As? {
		await customData.get(type)
	}

	/// Set custom data or parsed config.
	public func set<As: Sendable>(_ value: As) async {
		await customData.set(value)
	}
}

extension AppConfig {
	public struct HostUsage: RawRepresentable, Hashable, Equatable, Sendable {
		public static let request = Self(rawValue: "request")
		
		public var rawValue: String

		public init?(rawValue: String) {
			self.rawValue = rawValue
		}
	}
	
	public struct Host : Sendable {
		public static func == (lhs: AppConfig.Host, rhs: AppConfig.Host) -> Bool {
			lhs.host == rhs.host
		}

		public var host: String
		public var usage: HostUsage?
		public var raw: [String: JSON]?
		
		public init(host: String, usage: HostUsage? = nil, raw: [String: JSON]? = nil) {
			self.host = host
			self.usage = usage
			self.raw = raw
		}
		
		public init?(_ raw: [String: JSON]) {
			guard let host = raw[Keys.host]?.stringValue, !host.isEmpty else {
				return nil
			}
			let usage = (raw[Keys.usage]?.stringValue).flatMap(HostUsage.init(rawValue:))
			self.init(host: host, usage: usage, raw: raw)
		}
	}
}

public struct AppEncryptConfig: Codable, Equatable, Sendable {
	/// Generate string without `-`.
	/// - Parameter length: truncate prefix length, should less than 32.
	public static func generateUUIDString(length: UInt8? = nil) -> String {
		let id = UUID().uuidString.replacingOccurrences(of: "-", with: "")
		if let length = length, length < id.count {
			return String(id.prefix(Int(length)))
		}
		return id
	}

	public var name: String
	public var id: String
	public var secret: String
	
	public init(name: String? = nil, id: String, secret: String) {
		self.name = name ?? id
		self.id = id
		self.secret = secret
	}
}
