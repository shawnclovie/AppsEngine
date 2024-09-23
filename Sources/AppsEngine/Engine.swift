import Foundation
import NIO
import Vapor

/// Supported Envrionments:
/// - `RUNTIME_VERBOSE`: words separated with `,`
///   - `metric`: log all metric with `Logger.default`
///   - `logging`: log all log from `LoggingSystem` with `Logger.default`
///   - `route`: log registered route path while `EngineApp` prepared to serve.
public actor Engine {
	public typealias AppWillPrepareClosure = @Sendable (_ config: AppConfigSet) async -> Void

	public let application: Application

	public nonisolated let config: EngineConfig

	public let resources: Resource

	public let apps = AppHolder()

	/// The hook could be used to change configuration for the prepared app.
	public let appWillPrepareHook: AppWillPrepareClosure?

	let modules: [Module]
	private let configProvider: AppConfigProvider
	private let appUpdatorBuilder: AppConfigProvider.UpdatorBuilder?
	private let appDetector: EngineAppDetector

	public let apiMetric: APIMetricRecorder?

	var requestProcessor: RequestProcessor?
	var middlewares: [Vapor.Middleware] = []

	/// Create Server and prepare multi-app running environment.
	/// - Parameters:
	///   - appDetector: to detect app for response each request.
	///   - appUpdatorBuilder: build updator to update apps with app source from configuration.
	///     - Return `AppConfigLocalUpdator` for local.
	///     - or `AppConfigClosureUpdator` for make `AppConfig` by hard code.
	///     - or customized updator e.g. `ZippedAppConfigUpdater` from Example.
	public init(
		config: EngineConfig,
		modules: [Module],
		appDetector: EngineAppDetector,
		appUpdatorBuilder: AppConfigProvider.UpdatorBuilder? = nil,
		appWillPrepareHook: AppWillPrepareClosure? = nil,
		requestProcessor: RequestProcessor? = nil,
		databaseBuilder: Resource.DatabaseBuilder? = nil,
		storageBuilder: Resource.StorageBuilder? = nil
	) async throws {
		self.config = config
		var env = self.config.server.environment.map({ Environment(name: $0 ) })
		?? .production
		env.arguments = CommandInput(arguments: CommandLine.arguments).executablePath
		let verboseContainsLogging = config.verboseItems.contains("logging")
		let defaultLogger = config.defaultLogger
		LoggingSystem.bootstrap { (label: String) -> LogHandler in
			(verboseContainsLogging ? defaultLogger : Logger(outputers: []))
			.with(label: label)
		}
		WrapError.shouldCaptureCaller.store(config.verboseItems.contains("error_caller"), ordering: .sequentiallyConsistent)

		application = try await .make(env)
		self.appDetector = appDetector
		self.requestProcessor = requestProcessor
		self.modules = modules
		self.appUpdatorBuilder = appUpdatorBuilder
		self.appWillPrepareHook = appWillPrepareHook
		apiMetric = config.metric.map(DefaultAPIMetricRecorder.init(metric:))

		let logger = config.startupLogger.with(label: "\(Self.self)", concat: true)
		if let res = config.resource {
			logger.log(.info, "initialize Resource")
			do {
				resources = try await Resource(
					res,
					application: application,
					databaseBuilder: databaseBuilder,
					storageBuilder: storageBuilder)
			} catch {
				logger.log(.critical, "initialize Resource failed", .error(error))
				throw error
			}
		} else {
			resources = .init(groups: [:], storageBuilder: storageBuilder)
		}
		logger.log(.info, "initialize AppUpdator")
		let updator = try await appUpdatorBuilder?(config.appSource, resources) ?? AppConfigLocalUpdator()
		configProvider = AppConfigProvider(modules: modules, config: config, updator: updator)

		logger.log(.info, "initialize Modules")
		for i in self.modules.indices {
			do {
				try await self.modules[i].resourceDidFinishPrepare(self)
			} catch {
				throw WrapError(.internal, error, [Keys.description: .string("\(modules[i].moduleName).resourceDidFinishPrepare() failed"),
				])
			}
		}
		await configProvider.register(updateHandler: self)
		try await configProvider.startUpdate()
		logger.log(.info, "initialized")
	}

	deinit {
		application.shutdown()
	}

	/// Run Server and respond request.
	/// - Parameters:
	///   - requestProcessor: to process request and response if needed.
	public func runServer(
		defaultMaxBodySize: ByteCount = "10mb"
	) throws {
		var httpCFG = application.http.server.configuration
		httpCFG.shutdownTimeout = config.server.shutdownTimeout.amount
		httpCFG.reuseAddress = config.server.reuseAddress
		httpCFG.address = .hostname(config.server.host, port: config.server.port)
		application.http.server.configuration = httpCFG
		application.routes.defaultMaxBodySize = defaultMaxBodySize

		middlewares = application.middleware.resolve()
		application.responder.use { app in
			self
		}

		let ip = (try? SocketAddress.lanAddress())?.ipAddress ?? "unknown_ip"
		config.metric?.count("engine.run_server.\(ip)")
		config.startupLogger.log(
			.info, "engine.run_server",
			.init(Keys.ip, ip),
			.init("pid", ProcessInfo.processInfo.processIdentifier),
			.init(Keys.config, config.server))
		try application.run()
	}
}

extension Engine: Responder {
	nonisolated public func respond(to request: Request) -> EventLoopFuture<Response> {
		let fu = request.eventLoop.makePromise(of: Response.self)
		fu.completeWithTask {
			let detector = self.appDetector
			guard let appEnv = await detector.detectApp(request: request, in: self.apps) else {
				self.config.metric?.count("engine.unknown_app_request")
				let pairs = detector.unknownAppLog(request: request)
				self.config.defaultLogger.log(.warn, "unknown_app_request", pairs)
				return HTTPResponse.error(Errors.app_not_found).response
			}
			guard let app = await self.apps[appEnv.appID] else {
				self.config.metric?.count("engine.unknown_app_request.from_env")
				var pairs = detector.unknownAppLog(request: request)
				pairs.append(.init(Keys.env, appEnv))
				self.config.defaultLogger.log(.warn, "unknown_app_request", pairs)
				return HTTPResponse.error(Errors.app_not_found).response
			}
			return try await app.respond(to: request, appEnv).get()
		}
		return fu.futureResult
	}
}

extension Engine: AppConfigUpdateListener {
	public func updateDidFinish(rootPath: URL, result: AppConfigUpdateResult, removedAppIDs: Set<String>) async {
		let warningDir = self.config.workingDirectory.appendingPathComponent("apps_warning")
		var newApps: [String: EngineApp] = [:]
		for (appID, config) in result.updatedAppConfigs {
			let appPath = rootPath.appendingPathComponent(appID)
			let app = EngineApp(self, config: config)
			await app.writeWarningFileIfNeeded(path: warningDir.appendingPathComponent("\(appID).json"))
			self.config.metric?.count("\(app.config.core.metricName).app.new_app.ok", count: 1)
			await appWillPrepareHook?(app.config)
			do {
				try await app.prepare(middlewares: middlewares, in: self)
				newApps[appID] = app
			} catch {
				logNewAppFailure(logger: self.config.defaultLogger, appID: appID, appPath: appPath, error: error, when: "update")
			}
		}
		let oldApps = await apps.apps.values
		for app in oldApps {
			let appID = app.config.core.appID
			if newApps[appID] == nil && !removedAppIDs.contains(appID) {
				newApps[appID] = app
			}
		}
		await apps.appDidFinishUpdate(apps: newApps)
		await appDetector.appUpdateDidFinish(in: self)
	}
	
	private func logNewAppFailure(logger: Logger, appID: String, appPath: URL, error: Error, when: String) {
		logger.log(.error, "new App failed", .appID(appID), .error(error))
		config.metric?.count("\(appID).app.new_app.failed", count: 1)
		try? "when: \(when)\n\n\(error)".write(to: appPath, atomically: true, encoding: .utf8)
	}
}

extension Engine {
	public actor AppHolder: Sendable {
		public private(set) var apps: [String: EngineApp] = [:]

		subscript(appID: String) -> EngineApp? {
			apps[appID]
		}

		func appDidFinishUpdate(apps: [String: EngineApp]) {
			self.apps = apps
		}
	}
}

public protocol EngineAppDetector: Sendable {
	func appUpdateDidFinish(in engine: Engine) async
	func detectApp(request: Request, in apps: Engine.AppHolder) async -> AppEnvRef?
	func unknownAppLog(request: Request) -> [Log.Pair]
}

extension EngineAppDetector {
	public func appUpdateDidFinish(in engine: Engine) {
	}

	public func unknownAppLog(request: Request) -> [Log.Pair] {
		[]
	}
}

/// Detect app with `Host` header.
public actor HostBasedAppDetector: EngineAppDetector {
	public func extractHost(request: Request) -> String? {
		if shouldExtractDebugHost,
		   let host = request.headers.first(name: HTTP.Header.x_debug_host),
		   !host.isEmpty {
			return host
		}
		guard let host = request.url.host ?? request.headers.first(name: .host) else {
			return nil
		}
		if let index = host.firstIndex(of: ":") {
			return String(host[..<index])
		}
		return host
	}

	public private(set) var appHostMapping: [String: AppEnvRef] = [:]

	let shouldExtractDebugHost: Bool

	public init(config: EngineConfig) async {
		shouldExtractDebugHost = config.isOn(DebugFeatures.engine_extractDebugHost)
	}

	public func appUpdateDidFinish(in engine: Engine) async {
		var hostMapping: [String: AppEnvRef] = [:]
		for (appID, app) in await engine.apps.apps {
			var appHostMapping: [String: AppEnvRef] = [:]
			for (env, config) in await app.config.environments {
				for host in config.hosts.values where host.usage == .request {
					appHostMapping[host.host] = .init(appID, env)
				}
			}
			for host in app.config.core.hosts.values where host.usage == .request {
				appHostMapping[host.host] = .main(appID)
			}
			for (host, env) in appHostMapping {
				if let prevEnv = hostMapping[host] {
					engine.config.defaultLogger.log(.error, "host conflict", .init(Keys.host, host), .init("env1", prevEnv), .init("env2", env))
				} else {
					hostMapping[host] = env
				}
			}
		}
		appHostMapping = hostMapping
	}
	
	public func detectApp(request: Request, in apps: Engine.AppHolder) -> AppEnvRef? {
		guard let host = extractHost(request: request) else {
			return nil
		}
		return appHostMapping[host]
	}
	
	public func unknownAppLog(request: Request, in engine: Engine) -> [Log.Pair] {
		[.init(Keys.host, extractHost(request: request) ?? "")]
	}
}
