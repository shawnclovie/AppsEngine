import AppsEngine
import Foundation
import Fluent
import FluentSQL
import Vapor

extension Resource.Group {
	func sql() throws -> SQLDB { try sqlDB(of: "sql") }
	var cache: Application.Redis? {
		redis["shared"]
	}
}

struct TestModule: Module {
	static let headerAppEnv  = "app-env"

	actor TestData {
		static let shared = TestData()

		var initVar = 0

		func updateVar(_ v: Int) {
			initVar = v
		}
	}

	var moduleName: String { "test" }

	struct T1Model: Codable, SQLModel {
		static let schema = "test1"
		var id: Int
		var name: String
		var time: Time?
		var create_time: Time
	}

	var endpoints: [Endpoint] {
		let epgWS = Endpoint.Group(endpointPrefix: "test", pathPrefix: "test", endpoints: [
			Endpoint(websocket: ["ws"], TestWebSocketInvocation()),
		])
		var epgTest = Endpoint.Group(endpointPrefix: "test", pathPrefix: "test", endpoints: [
			Endpoint(.get(""), { ctx in
				print("initVar:", await TestData.shared.initVar,
					  "from engine config:", await ctx.engineConfig.get(TestData.self)?.initVar as Any)
				let cfg = await ctx.config.get(Config.self)!
				return .json(.ok, JSON.object([
					"enc": .array(ctx.config.encryptions.values.map({
						.object([Keys.id: .string($0.id), Keys.secret: .string($0.secret)])
					})),
					"attr1": .string(cfg.attr1),
				]))
			}),
			Endpoint(.get("match", "**"), { ctx in
				return .text(.ok, "\(ctx.request?.parameters.getCatchall() as Any)")
			}),
			Endpoint([.get("echo"), .post("echo")], name: "echo", { ctx in
				if ctx.request?.headers.contains(name: "throws") == true {
					throw WrapError(.internal, AnyError("throws"))
				}
				return .binary(.ok, await ctx.body() ?? .init())
			}),
			Endpoint(.get("hello", .var("name")), { ctx in
				ctx.logger.log(.info, "\(ctx.request?.url as Any)")
				return .text(.ok, ctx.request?.parameters.get("name") ?? "<none>")
			}),
			Endpoint(.get("hello1/:name"), { ctx in
				ctx.logger.log(.info, "\(ctx.request?.url as Any)")
				return .text(.ok, ctx.request?.parameters.get("name") ?? "<none>")
			}),
			Endpoint(.get("stream"), { ctx in
				.stream(.ok) { writer in
					_ = writer.write(.buffer(.init(string: "stream: ")))
					Task {
						for i in 0..<10 {
							let v = i.description
							_ = writer.write(.buffer(.init(string: v)))
							do {
								try await Task.sleep(nanoseconds: UInt64(1e6) * 100)
							} catch {}
						}
						_ = writer.write(.end)
					}
				}
			}),
			Endpoint(.get("async_stream"), { ctx in
				.stream(.ok) { (writer) async throws in
					try await writer.write(.buffer(.init(string: "async stream: ")))
					for i in 0..<10 {
						let v = i.description
						try await writer.write(.buffer(.init(string: v)))
						try await Task.sleep(nanoseconds: UInt64(1e6) * 100)
					}
					try await writer.write(.end)
				}
			}),
			// TODO: proxy as a fixed endpoint
		], middlewares: [
			ClosureMiddleware({ ctx in
				print("\(ctx.request?.url as Any) m1 before process")
				if ctx.request?.headers.contains(name: "m1throws") == true {
					throw WrapError(.internal, AnyError("m1throws"))
				}
				var res = await ctx.next()
				print("\(ctx.request?.url as Any) m1 after process")
				res.headers.replaceOrAdd(name: "m1foo", value: "bar")
				return res
			}),
			ClosureMiddleware({ ctx in
				print("\(ctx.request?.url as Any) m2 before process")
				var res = await ctx.next()
				print("\(ctx.request?.url as Any) m2 after process")
				res.headers.replaceOrAdd(name: "m2foo", value: "bar")
				return res
			}),
		])
		epgTest.append(
			ProcessA1(),
			ProcessA2(),
			Endpoint(.get("db"), respond(db:))
		)
		return epgWS.endpoints + epgTest.endpoints
	}

	func resourceDidFinishPrepare(_ engine: Engine) async throws {
		await TestData.shared.updateVar(Int(engine.config.rawData["service", "test", "test_data_var"].valueAsInt64 ?? 1))
		await engine.config.set(TestData.shared)
	}

	struct ProcessA1: EndpointProducer, RequestInvocation {
		var routes: [AppsEngine.Endpoint.Route] { [.get("a1")] }
		var invocation: AppsEngine.Endpoint.Invocation { .request(self) }

		func respond(to ctx: Context) async throws -> HTTPResponse {
			.text(.ok, "this is \(name)")
		}
	}

	struct ProcessA2: EndpointProducer, RequestInvocation {
		var routes: [AppsEngine.Endpoint.Route] { [.get("a2")] }
		var invocation: AppsEngine.Endpoint.Invocation { .request(self) }

		func respond(to ctx: Context) async throws -> HTTPResponse {
			.text(.ok, "this is \(name)")
		}
	}

	func respond(db ctx: Context) async throws -> HTTPResponse {
		let tableName = "test1"
		let db = try ctx.resources.defaultGroup!.sql()
		let now = ctx.startTime
		do {
			try await db.delete(from: tableName, {
				_ = $0.returning("*")
			}, onRow: {
				ctx.logger.log(.info, "delete returning", .init("cols", $0.allColumns))
			})
			try await db.executor.drop(table: tableName).run()
		} catch {
			ctx.logger.log(.warn, "delete and drop", .error(error))
		}

		try await db.executor.create(table: tableName)
			.column(definitions: [
				.init("id", dataType: .int, constraints: [.notNull]),
				.init("name", dataType: .text, constraints: [.notNull]),
				.init("time", dataType: .custom(SQLRaw("TIMESTAMP"))),
				.init(Keys.create_time, dataType: .custom(SQLRaw("TIMESTAMP"))),
			])
			.run()
		ctx.logger.log(.debug, "created table")
		let models = (0..<10).map({ (i: Int) in
			T1Model(id: i, name: i.description, time: i / 2 * 2 == i ? nil : .utc, create_time: now + TimeDuration.seconds(Int64(i)))
		})
		ctx.logger.log(.info, "insert",
					   .init("affect", try await db.insert(models: models)))
		try await db.update(from: T1Model.schema, {
			$0.whereEq("id", 5).set("name", to: "five")
			_ = $0.returning("*")
		}, onRow: {
			do {
				let res = try $0.decode(model: T1Model.self)
				ctx.logger.log(.info, "decode returning", .init("res", res))
			} catch {
				ctx.logger.log(.error, "decode returning", .error(error))
			}
		})
		for i in 0...1 {
			let updateResult = try await db.update(model: T1Model(id: 1000, name: String(repeating: "name", count: 3), time: nil, create_time: models[i].create_time), columns: [Keys.name], {
				$0.whereEq(Keys.id, i)
				$0.whereEq("time", models[i].time)
				$0.whereEq(Keys.create_time, models[i].create_time)
			})
			ctx.logger.log(.debug, "update \(i)", .init("affectRows", updateResult.affectRows))
		}
		do {
			let rows: [T1Model] = try await db.selectAll {
				$0.whereIn(Keys.create_time, [models[2].create_time, models[8].create_time])
			}
			ctx.logger.log(.debug, "select 2&8", .init("rows", rows))
		}
		var rows: [T1Model] = try await db.selectAll(orderBy: [("id", .ascending)]) {
			$0.where("time", .is, SQLDB.null)
		}
		rows += try await db.selectAll(orderBy: [("id", .ascending)]) {
			$0.where("time", .isNot, SQLDB.null)
		}
		let bytes = try JSONEncoder().encode(rows)
		return .binary(.ok, .init(data: bytes))
	}

	var supportEnvironment: Bool { true }
	
	func parseConfig(_ configSet: AppConfigSet, environment: (name: String, raw: [String: JSON])?) async -> AppConfigParseResult? {
		print("\(Self.self) parseConfig for env \(environment?.name ?? "main")")
		var config = Config()
		var raw = environment?.raw["config"]?.objectValue
		if raw == nil {
			raw = await configSet.core.raw
		}
		if let v = raw?["attr1"]?.stringValue {
			config.attr1 = v
		}
		return .init(config, warnings: [])
	}
	
	struct Config {
		var attr1 = ""
	}
}

struct TestWebSocketInvocation: WebSocketInvocation {
	func webSocketDidConnect(_ webSocket: WebSocket, on ctx: Context) async throws {
		print("webSocketDidConnect()")
	}
	func webSocket(_ webSocket: WebSocket, on ctx: Context, received upstream: WebSocketUpStream) async {
		print("webSocket(_:on:received:) upstream=\(upstream)")
	}
	
	func webSocket(_ webSocket: WebSocket, on ctx: Context, didClose error: Error?) {
		print("webSocket(_:on:didClose:) error=\(error as Any)")
	}
}

struct RouteModule: Module {
	var moduleName: String { "route" }
	
	var endpoints: [Endpoint] { [] }
	
	func parseConfig(_ configSet: AppConfigSet, environment: (name: String, raw: [String: JSON])?) -> AppConfigParseResult? {
		print("\(Self.self) parseConfig for env \(environment?.name ?? "main")")
		return .init(Config())
	}
	
	struct Config {
	}
	
	struct TestRequestProcessor: RequestProcessor {
		var decoder: (@Sendable (_ body: ByteBuffer) -> ByteBuffer?)?

		mutating func prepare(for app: EngineApp) async {
			print("\(self.self).prepare", await app.config.core.encryptions)
			decoder = { body in
				var buf = body
				guard var data = buf.readData(length: buf.readableBytes) else {
					return buf
				}
				data = Data(data.reversed())
				return .init(data: data)
			}
		}

		func processRequest(_ request: Request, _ body: ByteBuffer) -> ByteBuffer {
			decoder?(body) ?? body
		}
		
		func processResopnse(_ context: Context, _ response: HTTPResponse) -> HTTPResponse {
			response
		}
	}
}

struct AppInfo: StorageKey {
	typealias Value = AppInfo
	
	let appID: String
	let clientPlatform: String
	let clientVersion: Int
}

/// Detect app with AppInfo
actor AppInfoHeaderAppDetector: EngineAppDetector {
	static let headerAppInfo  = "app-info"

	func appUpdateDidFinish(in engine: Engine) async {
		await engine.config.defaultLogger.log(.info, "app updated", .any("app_ids", engine.apps.apps.keys.joined(separator: ",")))
	}

	func detectApp(request: Request, in apps: Engine.AppHolder) async -> AppEnvRef? {
		guard let rawInfo = request.headers.first(name: Self.headerAppInfo)
		else { return nil }
		let comps = rawInfo.split(separator: ":")
		guard comps.count >= 3
		else { return nil }
		let appEnvComps = comps[0].split(separator: ".", maxSplits: 2)
		let info = AppInfo(appID: String(appEnvComps[0]),
						   clientPlatform: String(comps[1]),
						   clientVersion: Int(comps[2]) ?? 0)
		await request.storage.setWithAsyncShutdown(AppInfo.self, to: info, onShutdown: nil)
		return .init(info.appID, appEnvComps.count > 1 ? String(appEnvComps[1]) : nil)
	}

	nonisolated func unknownAppLog(request: Request) -> [Log.Pair] {
		[.any("headers", request.headers)]
	}
}

struct ServerProcessProvider: Sendable, ServiceRegisterDataSource {
	public static var schema: String { "server_process" }

	let db: SQLDB

	init(_ engine: Engine) async throws {
		db = try await engine.resources.defaultGroup!.sql()
	}
	
	func loadAllModels() async throws -> [ServiceRegister.Model] {
		let rows = try await db.selectAll(columns: [
			Keys.node_id,
			Keys.name,
			Keys.ip,
			Keys.worker,
			Keys.startup_time,
			Keys.last_rent_time,
			Keys.extra,
		], from: Self.schema)
		return try rows.map { row in
			.init(nodeID: try row.decode(column: Keys.node_id),
				  name: try row.decode(column: Keys.name),
				  ip: try row.decode(column: Keys.ip),
				  worker: try row.decode(column: Keys.worker),
				  startupTime: try row.decode(column: Keys.startup_time),
				  lastRentTime: try row.decode(column: Keys.last_rent_time),
				  extra: try row.decode(column: Keys.extra))
		}
	}
	
	func insert(model: ServiceRegister.Model) async throws -> Int {
		try await db.insert(into: Self.schema, [
			Keys.node_id: model.nodeID,
			Keys.name: model.name,
			Keys.ip: model.ip,
			Keys.worker: model.worker,
			Keys.startup_time: model.startupTime,
			Keys.last_rent_time: model.lastRentTime,
			Keys.extra: model.extra,
		]).affectRows
	}
	
	func update(model: ServiceRegister.Model, wasStartupTime: Time) async throws -> Int {
		try await db.update(from: Self.schema, fieldAndValues: [
			Keys.name: model.name,
			Keys.ip: model.ip,
			Keys.worker: model.worker,
			Keys.last_rent_time: model.lastRentTime,
			Keys.extra: model.extra,
		], {
			$0.where(Keys.node_id, .equal, model.nodeID)
			$0.where(Keys.startup_time, .equal, wasStartupTime)
		}).affectRows
	}
	
	func updateRentTime(model: ServiceRegister.Model) async throws -> Int {
		try await db.update(from: Self.schema, {
			$0.set(Keys.last_rent_time, to: model.lastRentTime)
			$0.where(Keys.node_id, .equal, model.nodeID)
			$0.where(Keys.startup_time, .equal, model.startupTime)
		}).affectRows
	}
}
