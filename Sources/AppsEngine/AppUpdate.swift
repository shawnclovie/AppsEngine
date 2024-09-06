import Foundation

public protocol AppConfigUpdateListener: AnyObject, Sendable {
	func updateDidFinish(rootPath: URL, result: AppConfigUpdateResult, removedAppIDs: Set<String>) async
}

public protocol AppConfigUpdator: Sendable {
	/// Each raw `AppConfig`'s root path, default: `CWD/apps`.
	func updateRootPath(_ config: borrowing EngineConfig) -> URL

	/// Update each raw `AppConfig` with `input`.
	func update(_ config: borrowing EngineConfig, input: AppConfigUpdateInput) async throws -> AppConfigUpdateResult
}

extension AppConfigUpdator {
	public func updateRootPath(_ config: borrowing EngineConfig) -> URL {
		config.workingDirectory.appendingPathComponent(EngineConfig.defaultLocalAppDirectory)
	}
}

public struct AppConfigUpdateInput: Sendable{
	public let appSource: EngineConfig.AppSource
	public let rootPath: URL
	public let logger: Logger

	public let includesAppIDs: Set<String>
	public let appUpdateTimes: [String: Time]
	public let modules: [Module]
	public let skipIfNoChange: Bool
	
	public func includes(appID: String) -> Bool {
		includesAppIDs.isEmpty || includesAppIDs.contains(appID)
	}
	
	public func shouldUpdate(appID: String, updateTime: Time) -> Bool {
		if skipIfNoChange,
		   let current = appUpdateTimes[appID] {
			return updateTime > current
		}
		return true
	}
	
	public func testAppConfig(_ engineConfig: borrowing EngineConfig, directory: URL) async -> Result<AppConfigSet, WrapError> {
		do {
			let config = try AppConfig(engineConfig, rootPath: directory, environment: nil)
			let mods = modules
			return .success(await .init(core: config, modules: mods))
		} catch {
			return .failure(Errors.invalid_app_config.convertOrWrap(error))
		}
	}
}

public struct AppConfigUpdateResult : Sendable{
	public private(set) var updatedApps: [String: Time] = [:]
	public private(set) var updatedAppConfigs: [String: AppConfigSet] = [:]
	public private(set) var skippedApps: [String: WrapError] = [:]
	
	public init() {}

	@inlinable
	public mutating func skipSinceNotChanged(appID: String) {
		skip(appID: appID, since: WrapError(.not_modified, [Keys.app_id: .string(appID)]))
	}

	public mutating func skip(appID: String, since: WrapError) {
		skippedApps[appID] = since
	}

	public mutating func testDidFinish(appID: String, modifyTime: Time, _ result: Result<AppConfigSet, WrapError>) {
		switch result {
		case .success(let config):
			updatedApps[appID] = modifyTime
			updatedAppConfigs[appID] = config
		case .failure(let error):
			skip(appID: appID, since: error)
		}
	}
}

public actor AppConfigProvider: Sendable {
	public typealias UpdatorBuilder = (_ appSource: EngineConfig.AppSource, _ resources: Resource) async throws -> AppConfigUpdator

	let config: EngineConfig
	let modules: [Module]
	private var appUpdateTimes: [String: Time] = [:]
	private let updator: AppConfigUpdator

	var includesAppIDs: Set<String> = []
	private var isUpdating = false
	private var updateHandlers: [AppConfigUpdateListener] = []

	init(modules: [Module], config: consuming EngineConfig, updator: AppConfigUpdator) {
		self.config = config
		self.modules = modules
		self.updator = updator
	}
	
	public var appIDs: [String] { .init(appUpdateTimes.keys) }

	public func register(updateHandler: AppConfigUpdateListener) {
		updateHandlers.append(updateHandler)
	}
	
	public func unregister(updateHandler: AppConfigUpdateListener) {
		if let index = updateHandlers.firstIndex(where: { $0 === updateHandler }) {
			updateHandlers.remove(at: index)
		}
	}
	
	func startUpdate() async throws {
		if case .array(let appIDs) = config.debugFeature(DebugFeatures.appConfig_includesAppIDs) {
			includesAppIDs = Set(appIDs.compactMap(\.stringValue))
		}
		_ = try await updateApps(config.startupLogger, includesAppIDs: includesAppIDs)
		if config.appSource.pullInterval.seconds > 0 {
			scheduleNextUpdate()
		}
	}
	
	func scheduleNextUpdate() {
		let pullInterval = config.appSource.pullInterval
		let logger = config.defaultLogger
		Task.detached(priority: .background) {
			do {
				try await Task.sleep(nanoseconds: UInt64(pullInterval.nanoseconds))
				_ = try await self.updateApps(logger, includesAppIDs: self.includesAppIDs)
			} catch {
				logger.log(.error, "\(Self.self).updateApps: failed", .error(error))
			}
			await self.scheduleNextUpdate()
		}
	}

	public func updateApps(_ logger: Logger,
						   includesAppIDs: Set<String> = [],
						   skipIfNoChange: Bool = true) async throws -> AppConfigUpdateResult {
		isUpdating = true
		defer {
			isUpdating = false
		}
		let rootPath = updator.updateRootPath(config)
		let logger = logger.with(label: "updator.\(type(of: updator))")
		logger.log(.info, "update apps", .init("rootPath", rootPath))
		let result = try await updator.update(config, input: .init(
			appSource: config.appSource,
			rootPath: rootPath,
			logger: logger,
			includesAppIDs: includesAppIDs,
			appUpdateTimes: appUpdateTimes,
			modules: modules,
			skipIfNoChange: skipIfNoChange))
		let removedAppIDs = appUpdateTimes.keys.filter({
			result.updatedApps[$0] == nil && result.skippedApps[$0] == nil
		})
		if !result.updatedApps.isEmpty {
			for (appID, updateTime) in result.updatedApps {
				appUpdateTimes[appID] = updateTime
			}
		}
		for appID in removedAppIDs {
			appUpdateTimes.removeValue(forKey: appID)
		}
		
		await notifyUpdateDidFinish(rootPath: rootPath, result: result, removedAppIDs: Set(removedAppIDs), serial: true)

		var logPairs: [Log.Pair] = [.init("apps", appIDs.joined(separator: ","))]
		if !result.skippedApps.isEmpty {
			logPairs.append(.init("skipped_apps", result.skippedApps))
		}
		logger.log(.info, "\(Self.self) updateApps: done", logPairs)
		return result
	}
	
	private func notifyUpdateDidFinish(rootPath: URL, result: AppConfigUpdateResult, removedAppIDs: Set<String>, serial: Bool) async {
		guard !result.updatedApps.isEmpty || !removedAppIDs.isEmpty else {
			return
		}
		for hnd in updateHandlers {
			if serial {
				await hnd.updateDidFinish(rootPath: rootPath, result: result, removedAppIDs: removedAppIDs)
			} else {
				Task(priority: .background) {
					await hnd.updateDidFinish(rootPath: rootPath, result: result, removedAppIDs: removedAppIDs)
				}
			}
		}
	}
}

public struct AppConfigClosureUpdator: AppConfigUpdator {
	public typealias Closure = @Sendable (_ config: borrowing EngineConfig, _ input: AppConfigUpdateInput) async throws -> AppConfigUpdateResult

	public let closure: Closure

	public init(closure: @escaping Closure) {
		self.closure = closure
	}

	public func update(_ config: borrowing EngineConfig, input: AppConfigUpdateInput) async throws -> AppConfigUpdateResult {
		try await closure(config, input)
	}
}

public struct AppConfigLocalUpdator: AppConfigUpdator {
	public typealias WillBeginClosure = @Sendable (_ input: AppConfigUpdateInput) -> Void
	public typealias DidFinishClosure = @Sendable (_ input: AppConfigUpdateInput, _ result: inout AppConfigUpdateResult) -> Void

	public var willBeginUpdate: WillBeginClosure?
	public var didFinishUpdate: DidFinishClosure?

	public init() {}

	public func update(_ config: borrowing EngineConfig, input: AppConfigUpdateInput) async throws -> AppConfigUpdateResult {
		willBeginUpdate?(input)
		var result = AppConfigUpdateResult()
		let resKeys: Set<URLResourceKey> = [.isDirectoryKey, .contentModificationDateKey]
		var files: [URL] = []
		if FileManager.default.fileExists(atPath: input.rootPath.path) {
			input.logger.log(.debug, "reloading apps from local", .init("root_path", input.rootPath))
			files = try FileManager.default.contentsOfDirectory(at: input.rootPath, includingPropertiesForKeys: .init(resKeys))
		} else {
			input.logger.log(.info, "local directory not exists", .init("root_path", input.rootPath))
		}
		for file in files {
			let stat = try file.resourceValues(forKeys: resKeys)
			guard stat.isDirectory == true else { continue }
			let appID = file.lastPathComponent
			guard let modifyTime = stat.contentModificationDate.map(Time.init) else {
				continue
			}
			guard input.includes(appID: appID) else {
				continue
			}
			guard input.shouldUpdate(appID: appID, updateTime: modifyTime) else {
				result.skipSinceNotChanged(appID: appID)
				continue
			}
			result.testDidFinish(appID: appID, modifyTime: modifyTime,
								 await input.testAppConfig(config, directory: file))
		}
		didFinishUpdate?(input, &result)
		return result
	}
}
