//
//  ServiceRegister.swift
//  
//
//  Created by Shawn Clovie on 14/8/2022.
//

import Foundation
import NIO

public protocol ServiceRegisterDataSource {
	var worker: ServiceRegister.Worker { get }
	
	func loadAllModels() async throws -> [ServiceRegister.Model]

	/// Insert the model, nodeID should be primiry key or unique index.
	func insert(model: ServiceRegister.Model) async -> ServiceRegister.ExecuteResult

	/// Update the model, should with condition: `WHERE nodeID=model.nodeID AND startup_time=model.startupTime`
	func update(model: ServiceRegister.Model, wasStartupTime: Time) async -> ServiceRegister.ExecuteResult

	func updateRentTime(model: ServiceRegister.Model) async -> ServiceRegister.ExecuteResult
}

extension ServiceRegisterDataSource {
	public var worker: ServiceRegister.Worker { .workingDirectory }
}

public final class ServiceRegister {
	public enum Worker {
		/// Get worker with last 2 components of working directory.
		case workingDirectory
		/// Get worker with particular name.
		case named(String)
		
		func get(_ config: EngineConfig) -> String {
			switch self {
			case .workingDirectory:
				let cwd = config.workingDirectory
				let comp1 = cwd.lastPathComponent
				let comp2 = cwd.deletingLastPathComponent().lastPathComponent
				return PathComponents.systemPath(comp2, comp1).joined()
			case .named(let name):
				return name
			}
		}
	}
	
	static let moduleName = "service_register"
	static let rentInterval = TimeDuration.minutes(1)
	static let rentThreshold = TimeDuration.minutes(10)
	static let maxTryTimes = 50
	static let retryDelay = TimeDuration.milliseconds(10)
	
	/// Initialize ServiceRegister and Snowflake.
	///
	/// - Parameters:
	///   - dataSource: to access `Model` if it is not `nil`, or use local mode - calculate Snowflake Node ID with lan IP and PID.
	public static func initialize(_ config: EngineConfig, dataSource: ServiceRegisterDataSource?) async throws {
		let ip = try SocketAddress.lanAddress()
		guard let dataSource else {
			await resetSnowflake(config, nodeID: produceNodeIndexWithPID(ip: ip), logger: config.startupLogger)
			return
		}
		let inst = ServiceRegister(config, dataSource: dataSource, ip: ip)
		try await inst.register(logger: config.startupLogger, initializing: true)
	}

	let config: EngineConfig
	let dataSource: ServiceRegisterDataSource
	let ip: SocketAddress
	let worker: String
	var model: Model?

	private init(_ config: EngineConfig, dataSource: ServiceRegisterDataSource, ip: SocketAddress) {
		self.config = config
		self.dataSource = dataSource
		self.ip = ip
		self.worker = dataSource.worker.get(config)
	}
	
	func register(logger: Logger?, initializing: Bool) async throws {
		var tryCount = 0
		repeat {
			tryCount += 1
			let result = await register()
			switch result {
			case .done(let nodeID):
				await Self.resetSnowflake(config, nodeID: nodeID, logger: logger)
				if initializing {
					Task {
						await runRentWorker()
					}
				}
			case .retry(let err):
				logger?.log(.error, "\(Self.moduleName) register failed: retry",
						   .error(err), .init("ip", ip), .init("worker", worker))
				if tryCount < Self.maxTryTimes {
					try? await Task.sleep(nanoseconds: UInt64(Self.retryDelay.nanoseconds))
					continue
				}
				throw err
			case .fallback:
				await Self.resetSnowflake(config, nodeID: produceNodeIndexWithPID(ip: ip), logger: logger)
			}
			break
		} while true
	}
	
	/// Initilaize Snowflake node id.
	/// - Parameters:
	///   - nodeID: the index would be part of generated snowflake id, it should between [0...1023] (10 bits).
	public static func resetSnowflake(_ config: EngineConfig, nodeID: UInt16, logger: Logger? = nil) async {
		logger?.log(.info, "\(moduleName) resetSnowflake", .init(Keys.node_id, nodeID))
		await config.setSnowflake(node: Int64(nodeID))
	}

	enum RegisterResult {
		case done(UInt16), retry(WrapError), fallback
	}

	private func register() async -> RegisterResult {
		let models: [Model]
		do {
			models = try await dataSource.loadAllModels()
		} catch {
			return .retry(Errors.database.convertOrWrap(error))
		}
		let now = Time()
		var occurNodeIDs = Set<UInt16>()
		var reuseModel: Model?
		var canOccurModelIndex: Int?
		for (i, model) in models.enumerated() {
			if model.isSame(ip: ip) && model.worker == worker {
				reuseModel = model
				break
			}
			occurNodeIDs.insert(model.nodeID)
			if !model.isLiving(now) && canOccurModelIndex == nil {
				canOccurModelIndex = i
			}
		}
		var isCreating = false
		var model: Model
		if let reuseModel = reuseModel {
			model = reuseModel
		} else {
			if let nodeID = findAvailableNodeID(occurNodeIDs) {
				model = .init(nodeID: nodeID, name: config.name, ip: ip, worker: worker, now: now)
				isCreating = true
			} else if let canOccurModelIndex = canOccurModelIndex {
				model = models[canOccurModelIndex]
				model.updateBasic(name: config.name, ip: ip, worker: worker)
			} else {
				return .fallback
			}
		}
		model.updateExtra()
		let result: ExecuteResult
		if isCreating {
			result = await dataSource.insert(model: model)
		} else {
			let prevStartupTime = model.startupTime
			model.updateStartupTime(now: now)
			result = await dataSource.update(model: model, wasStartupTime: prevStartupTime)
		}
		switch result {
		case .failure(let err):
			return .retry(Errors.database.convertOrWrap(err))
		case .notChanged:
			return .retry(WrapError(.not_modified))
		case .ok:
			self.model = model
			return .done(model.nodeID)
		}
	}

	func findAvailableNodeID(_ occurNodeIDs: Set<UInt16>) -> UInt16? {
		for i in 0...Snowflake.nodeMax {
			if !occurNodeIDs.contains(UInt16(i)) {
				return UInt16(i)
			}
		}
		return nil
	}
	
	func runRentWorker() async {
		repeat {
			await rent()
			try? await Task.sleep(nanoseconds: UInt64(Self.rentInterval.nanoseconds))
		} while true
	}
	
	func rent() async {
		guard var model = model else {
			return
		}
		model.lastRentTime = .utc
		let result = await dataSource.updateRentTime(model: model)
		switch result {
		case .ok:
			self.model = model
		case .notChanged:
			do {
				try await register(logger: config.defaultLogger, initializing: false)
			} catch {
				logRendFailure(error)
			}
		case .failure(let err):
			logRendFailure(err)
		}
	}
	
	func logRendFailure(_ error: Error) {
		config.defaultLogger.log(.error, "\(Self.moduleName) update rent failed", .error(error), .init("model", model))
		config.metric?.countCritical("\(Self.moduleName).rent_failed")
	}
}

extension ServiceRegister {
	public enum ExecuteResult {
		case ok
		case notChanged
		case failure(Error)
		
		public init(from result: Result<Int, Error>) {
			switch result {
			case .success(let affectCount):
				self = affectCount == 0 ? .notChanged : .ok
			case .failure(let error):
				self = .failure(error)
			}
		}
	}
	
	public struct Model : Sendable{
		public var nodeID: UInt16
		public var name: String
		public var ip: String
		public var worker: String
		public var startupTime: Time
		public var lastRentTime: Time
		public var extra: [String: JSON]
		
		public init(nodeID: UInt16,
					name: String, ip: String, worker: String,
					startupTime: Time, lastRentTime: Time,
					extra: [String: JSON] = [:]) {
			self.nodeID = nodeID
			self.name = name
			self.ip = ip
			self.worker = worker
			self.startupTime = startupTime
			self.lastRentTime = lastRentTime
			self.extra = extra
		}
		
		public init(nodeID: UInt16, name: String, ip: SocketAddress, worker: String, now: Time) {
			self.init(nodeID: nodeID, name: name,
					  ip: ip.ipAddress ?? ip.description, worker: worker,
					  startupTime: now, lastRentTime: now)
		}
		
		func isSame(ip: SocketAddress) -> Bool {
			self.ip == ip.ipAddress || self.ip == ip.description
		}
		
		func isLiving(_ now: Time) -> Bool {
			now.diff(lastRentTime) < ServiceRegister.rentThreshold
		}

		mutating func updateBasic(name: String, ip: SocketAddress, worker: String) {
			self.name = name
			self.ip = ip.ipAddress ?? ip.description
			self.worker = worker
		}
		
		mutating func updateExtra() {
			let proc = ProcessInfo.processInfo
			extra["args"] = .array(proc.arguments.map(JSON.string))
			extra["pid"] = proc.processIdentifier.jsonValue
			extra["hostname"] = .string(proc.hostName)
			extra["os"] = .string(proc.operatingSystemVersionString)
			if let sys = SystemInfo() {
				extra["machine"] = .string(sys.machine)
			}
		}
		
		mutating func updateStartupTime(now: Time) {
			startupTime = now
			lastRentTime = now
		}
	}
}

/// Product node index with LanIP and PID.
///
/// The function may produce duplicate value while multiple deployment.
private func produceNodeIndexWithPID(ip: SocketAddress) -> UInt16 {
	let seedBits: Int64 = 5
	let maxSeed: Int64 = 1 << seedBits

	var ipSeed = Int64(127001)
	if let addr = ip.ipAddress,
	   let seed = Int64(addr.replacingOccurrences(of: ".", with: "")) {
		ipSeed = seed
	}
	let pid = ProcessInfo.processInfo.processIdentifier
	return UInt16((ipSeed % maxSeed) << seedBits) + UInt16(Int64(pid) % maxSeed)
}
