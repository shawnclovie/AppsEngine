import Fluent
import Foundation
@preconcurrency import Redis
import Vapor

public final class Resource: Sendable {
	public enum Error: String, Swift.Error {
		case no_storageBuilder_provided = "no storageBuilder provided"
		case no_storageBuilder_defined = "no storageBuilder defined"
		case storage_url_malformed
		case not_found_named_database
		case not_found_named_storage
	}

	public typealias DatabaseBuilder = @Sendable (_ config: Resource.DatabaseConfig) throws -> DatabaseConfiguration
	public typealias StorageBuilder = @Sendable (_ source: ObjectStorageSource) async throws -> ObjectStorageProvider

	public let groups: [String: Group]

	let storageBuilder: StorageBuilder?

	public init(groups: [String: Group], storageBuilder: StorageBuilder?) {
		self.groups = groups
		self.storageBuilder = storageBuilder
	}

	public convenience init(
		_ config: Config,
		application: Application,
		databaseBuilder: Resource.DatabaseBuilder?,
		storageBuilder: StorageBuilder?
	) async throws {
		var groups: [String: Group] = [:]
		for it in config.groups {
			groups[it.key] = try await .init(it.value, application: application, databaseBuilder: databaseBuilder, storageBuilder: storageBuilder)
		}
		self.init(groups: groups, storageBuilder: storageBuilder)
	}
	
	public func buildStorage(source: ObjectStorageSource) async throws -> ObjectStorageProvider {
		guard let builder = storageBuilder else {
			throw WrapError(.invalid_engine_config, Error.no_storageBuilder_provided)
		}
		return try await builder(source)
	}

	public var defaultGroup: Group? { groups[Keys.default] }

	/// - Format:
	///   - `{"url": string, "base_url": string?}`
	///   - `{"object_storage_ref": string, "path": string}`
	public func objectStorageProvider(from value: [String: JSON]) async throws -> ObjectStorageProvider {
		if let url = value[Keys.url]?.stringValue,
		   let baseURL = value[Keys.base_url]?.stringValue {
			do {
				guard let storageBuilder else {
					throw WrapError(.invalid_engine_config, Error.no_storageBuilder_defined)
				}
				let source = try ObjectStorageSource(urlString: url, baseURL: baseURL)
				return try await storageBuilder(source)
			} catch {
				throw WrapError(.invalid_engine_config, Error.storage_url_malformed, wrapped: error)
			}
		}
		if let path = value[Keys.path]?.stringValue,
		   let nameOfOS = (value[Keys.object_storage_ref]?.stringValue) {
			let names = nameOfOS.split(separator: ".").map(String.init)
			guard names.count >= 2,
				  let group = groups[names[0]],
				  var provider = group.objectStorages[names[1]] else {
				throw WrapError(.invalid_engine_config, Error.not_found_named_storage, [Keys.name: .string(nameOfOS)])
			}
			provider.source.append(path: path)
			return provider
		}
		throw WrapError(.invalid_parameter, "should have key (\(Keys.object_storage_ref) and \(Keys.path)) or (\(Keys.url) and \(Keys.base_url))")
	}

	public struct Group: Sendable {
		public let databases: [String: Database]
		public let redis: [String: Application.Redis]
		public let objectStorages: [String: ObjectStorageProvider]
		
		let config: GroupConfig
		
		init(_ config: GroupConfig,
			 application: Application,
			 databaseBuilder: Resource.DatabaseBuilder?,
			 storageBuilder: StorageBuilder?) async throws {
			databases = try .init(config.databases.map({ it in
				guard let builder = databaseBuilder else {
					throw AnyError("no databaseBuilder given but configured databases")
				}
				return (it.key, try it.value.connect(application: application, isDefault: false, databaseBuilder: builder))
			}), uniquingKeysWith: { l, r in r })
			redis = try .init(config.redis.map({ it in
				(it.key, try it.value.connect(application: application))
			}), uniquingKeysWith: { l, r in r })
			var objectStorages: [String: ObjectStorageProvider] = [:]
			for it in config.objectStorages {
				guard let builder = storageBuilder else {
					throw AnyError("no storageBuilder given but configured storages")
				}
				objectStorages[it.key] = try await builder(it.value)
			}
			self.objectStorages = objectStorages
			self.config = config
		}
		
		public func sqlDB(of: String) throws -> SQLDB {
			guard let db = databases[of] else {
				throw WrapError(.invalid_engine_config, Error.not_found_named_database, [Keys.name: .string(of)])
			}
			return try SQLDB(instance: db)
		}
	}
	
	public struct Config: Sendable {
		public var groups: [String: GroupConfig]

		public init(groups: [String : GroupConfig]) {
			self.groups = groups
		}

		init(_ config: [String: JSON]) throws {
			self.init(groups: [:])
			for it in config {
				guard  let cfg = it.value.objectValue else {
					throw AnyError("group(\(it.key)) should be dictionary")
				}
				do {
					groups[it.key] = try .init(id: it.key, cfg)
				} catch {
					throw AnyError("group(\(it.key)) invalid", wrap: error)
				}
			}
		}
	}
	
	public struct GroupConfig: Sendable {
		public let id: String
		public var databases: [String: DatabaseConfig] = [:]
		public var redis: [String: RedisConfig] = [:]
		public var objectStorages: [String: ObjectStorageSource] = [:]

		public init(id: String, databases: [DatabaseConfig], redis: [RedisConfig], objectStorages: [String: ObjectStorageSource]) {
			self.id = id
			for database in databases {
				self.databases[database.id] = database
			}
			for it in redis {
				self.redis[it.id] = it
			}
			self.objectStorages = objectStorages
		}

		public init(id: String, _ config: [String: JSON]) throws {
			if let cfg = config[Keys.database]?.objectValue {
				for it in cfg {
					guard let cfgDB = it.value.objectValue else {
						throw AnyError("database(\(it.key)) should be dictionary")
					}
					do {
						databases[it.key] = try .init(id: it.key, cfgDB)
					} catch {
						throw AnyError("database(\(it.key)) invalid", wrap: error)
					}
				}
			}
			if let cfg = config[Keys.redis]?.objectValue {
				for it in cfg {
					guard let cfgDB = it.value.objectValue else {
						throw AnyError("redis(\(it.key)) should be dictionary")
					}
					do {
						redis[it.key] = try .init(id: it.key, cfgDB)
					} catch {
						throw AnyError("redis(\(it.key)) invalid", wrap: error)
					}
				}
			}
			if let cfg = config[Keys.object_storage]?.objectValue {
				for it in cfg {
					let source: ObjectStorageSource
					do {
						switch it.value {
						case .object(let cfgDB):
							source = try .init(cfgDB)
						case .string(let url):
							source = try .init(urlString: url, baseURL: nil)
						default:
							throw AnyError("object_storage(\(it.key)) should be dictionary")
						}
					} catch {
						throw AnyError("storage(\(it.key)) invalid", wrap: error)
					}
					objectStorages[it.key] = source
				}
			}
			self.id = id
		}
	}
	
	public struct ObjectStorageConfig {
		public let id: String
		public var rawData: [String: JSON]

		public init(id: String, rawData: [String : JSON]) {
			self.id = id
			self.rawData = rawData
		}
	}
	
	public struct DatabaseConfig: Sendable {
		public let id: String
		public var url: URL
		public var rawData: [String: JSON]

		public init(id: String, url: URL) {
			self.id = id
			self.url = url
			self.rawData = [:]
		}

		public init(id: String, _ config: [String: JSON]) throws {
			guard let value = config[Keys.url]?.stringValue else {
				throw AnyError("'url' empty")
			}
			guard let url = URL(string: value) else {
				var desc = "'url'(\(value)) invalid"
				if value.contains("%") {
					desc += ", you could try replace '%' as '%25'"
				}
				throw AnyError(desc)
			}
			self.url = url
			self.id = id
			rawData = config
		}

		func connect(application: Application, isDefault: Bool, databaseBuilder: Resource.DatabaseBuilder) throws -> Database {
			let dbcfg = try databaseBuilder(self)
			let dbID = DatabaseID(string: id)
			application.databases.use(dbcfg, as: dbID, isDefault: isDefault)
			guard let db = application.databases.database(dbID, logger: application.logger, on: application.eventLoopGroup.any()) else {
				throw AnyError("fetch database(\(id)) failed")
			}
			return db
		}
	}
	
	public struct RedisConfig: Sendable {
		public let id: String
		public var url: URL
		public var pool = RedisConfiguration.PoolOptions()

		public init(id: String, url: URL, pool: RedisConfiguration.PoolOptions = RedisConfiguration.PoolOptions()) {
			self.id = id
			self.url = url
			self.pool = pool
		}

		public init(id: String, _ config: [String: JSON]) throws {
			guard let value = config[Keys.url]?.stringValue else {
				throw AnyError("'url' empty")
			}
			guard let url = URL(string: value) else {
				throw AnyError("'url'(\(value)) invalid")
			}
			self.url = url
			self.id = id
			if let value = config[Keys.pool]?.objectValue {
				if let count = config["max_active_conns"]?.valueAsInt64 {
					pool.maximumConnectionCount = .maximumActiveConnections(Int(count))
				} else if let count = config["max_preserved_conns"]?.valueAsInt64 {
					pool.maximumConnectionCount = .maximumPreservedConnections(Int(count))
				}
				if let count = value["min_idle_conns"]?.valueAsInt64 {
					pool.minimumConnectionCount = Int(count)
				}
			}
		}
		
		func connect(application: Application) throws -> Application.Redis {
			let redis = application.redis(.init(id))
			redis.configuration = try RedisConfiguration(url: url, pool: pool)
			return redis
		}
	}
}
