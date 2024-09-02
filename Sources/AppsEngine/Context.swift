import Vapor

public protocol RequestProcessor: Sendable {
	/// Prepare decoder and encoder for an app, would be called in `EngineApp.prepare`.
	mutating func prepare(for app: EngineApp) async

	/// Process request data, used to decode.
	func processRequest(_ request: Request, _ body: ByteBuffer) throws -> ByteBuffer

	/// Process response data, used to encode.
	func processResopnse(_ context: Context, _ response: HTTPResponse) throws -> HTTPResponse
}

public final class Context: Sendable {
	public enum Error: String, Swift.Error {
		case no_body
		case no_content_type
		case request_not_supported
		case websocket_not_supported
	}

	private let engine: Engine
	public let configSet: AppConfigSet?
	public let config: AppConfig
	public let userID: String?
	public let traceID: String
	public let logger: Logger
	public let startTime: Time
	private let debugIgnoreBodyProcess: Bool

	/// Processing endpoint.
	///
	/// Valid only on request processing context.
	public let endpoint: Endpoint?

	/// `Request` if serving a request
	///
	/// Valid only in endpoint processing context
	public let request: Request

	actor Vars {
		var requestProcessor: RequestProcessor?
		var body: ByteBuffer?

		var middlewareCallIndex = -1
		var lastResponse: HTTPResponse?

		var storage: [ObjectIdentifier: Any] = [:]

		var cachedResource: Resource.Group?

		func processedBody(request: Request) async throws -> ByteBuffer? {
			guard var body else {
				return nil
			}
			if let requestProcessor {
				let new = try requestProcessor.processRequest(request, body)
				set(body: new, nil)
				body = new
			}
			return body
		}

		func set(body: ByteBuffer?, _ requestProcessor: RequestProcessor?) {
			self.requestProcessor = requestProcessor
			self.body = body
		}

		func increaseMiddlewareCallIndex() -> Int {
			middlewareCallIndex += 1
			return middlewareCallIndex
		}

		func set(lastResponse: HTTPResponse) {
			self.lastResponse = lastResponse
		}

		func get<As: Sendable>(_ valueType: As.Type) -> As? {
			storage[ObjectIdentifier(valueType)] as? As
		}

		func set<As: Sendable>(_ value: As) {
			storage[ObjectIdentifier(type(of: value))] = value
		}
	}

	let vars = Vars()

	public convenience init(_ engine: Engine, config: AppConfig, userID: String?, startTime: Time) async {
		await self.init(
			engine,
			endpoint: nil,
			request: .init(application: engine.application,
						   on: engine.application.eventLoopGroup.any()),
			configSet: nil, config: config,
			requestProcessor: nil,
			userID: userID, startTime: startTime)
	}

	public convenience init(_ engine: Engine, configSet: AppConfigSet, userID: String?, startTime: Time) async {
		await self.init(
			engine,
			endpoint: nil,
			request: .init(application: engine.application,
						   on: engine.application.eventLoopGroup.any()),
			configSet: configSet, config: configSet.core,
			requestProcessor: nil,
			userID: userID, startTime: startTime)
	}

	convenience init(
		request: Request, endpoint: Endpoint,
		_ engine: Engine, configSet: AppConfigSet,
		requestProcessor: RequestProcessor?,
		environment: String?
	) async {
		let config = await configSet.config(environment: environment)
		await self.init(
			engine, endpoint: endpoint, request: request, configSet: configSet,
			config: config ?? configSet.core,
			requestProcessor: requestProcessor,
			userID: nil,
			startTime: Time(offset: configSet.core.timeOffset ?? engine.config.timezone.secondsFromGMT()))
	}

	init(_ engine: Engine,
		 endpoint: Endpoint?,
		 request: Request,
		 configSet: AppConfigSet?, config: AppConfig,
		 requestProcessor: RequestProcessor?,
		 userID: String?, startTime: Time
	) async {
		self.engine = engine
		self.configSet = configSet
		self.config = config
		self.userID = userID
		traceID = await engine.config.snowflakeNode.generate().base36
		self.logger = engine.config.defaultLogger.with(
			label: "\(config.appID).request.\(traceID)", concat: true,
			trace: .init(on: startTime))
		self.startTime = startTime
		self.endpoint = endpoint
		self.request = request
		debugIgnoreBodyProcess = engine.config.isOn(DebugFeatures.engine_ignoreBodyProcess)

		await vars.set(body: request.body.data, shouldIgnoreBodyProcess ? nil : requestProcessor)
	}

	public var appID: String { config.appID }
	public var resources: Resource { engine.resources }
	public var engineConfig: EngineConfig { engine.config }

	public func body() async -> ByteBuffer? {
		await vars.body
	}

	/// `WebSocket` if serving WebSocket.
	public func webSocket() async -> WebSocket? {
		await get(WebSocket.self)
	}

	public func get<As: Sendable>(_ valueType: As.Type) async -> As? {
		await vars.get(valueType)
	}

	public func set<As: Sendable>(_ value: As) async {
		await vars.set(value)
	}

	var shouldIgnoreBodyProcess: Bool {
		debugIgnoreBodyProcess && anyToBool(request.headers[HTTP.Header.x_debug_ignore_body_process]) == true
	}

	public func requestBody() async throws -> ByteBuffer? {
		try await vars.processedBody(request: request)
	}

	public func decode<AsType: Decodable>(defaultContentType: HTTPMediaType? = nil) async throws -> AsType {
		try await decodeAs(AsType.self, defaultContentType: defaultContentType)
	}

	public func decodeAs<AsType: Decodable>(
		_ type: AsType.Type,
		defaultContentType: HTTPMediaType? = nil
	) async throws -> AsType {
		guard let body = try await requestBody() else {
			throw WrapError(.bad_request, Error.no_body)
		}
		guard let contentType = request.headers.contentType ?? defaultContentType else {
			throw WrapError(.bad_request, Error.no_content_type)
		}
		do {
			let decoder = try ContentConfiguration.global.requireDecoder(for: contentType)
			let obj = try decoder.decode(type, from: body, headers: request.headers)
			return obj
		} catch {
			switch error {
			case let error as DecodingError:
				throw WrapError(.invalid_parameter, error.reason)
			default:
				throw WrapError(.invalid_parameter, error)
			}
		}
	}

	func serve() async -> HTTPResponse {
		guard case .request(_) = endpoint?.invocation else {
			return .error(WrapError(.forbidden, Error.request_not_supported))
		}
		return await next()
	}

	func serve(webSocket: WebSocket) async {
		guard case .webSocket(let inv) = endpoint?.invocation else {
			await close(webSocket: webSocket, response: .error(WrapError(.forbidden, Error.websocket_not_supported)))
			return
		}
		await set(webSocket)
		let res = await next()
		guard res.error == nil else {
			await close(webSocket: webSocket, response: res)
			return
		}
		webSocket.onClose.whenComplete { (result) in
			var err: Swift.Error?
			if case .failure(let e) = result {
				err = e
			}
			inv.webSocket(webSocket, on: self, didClose: err)
		}
		webSocket.onPing { (ws, buf) async in
			await inv.webSocket(ws, on: self, received: .ping(buf))
		}
		webSocket.onPong { (ws, buf) async in
			await inv.webSocket(ws, on: self, received: .pong(buf))
		}
		webSocket.onText { (ws, text) async in
			await inv.webSocket(ws, on: self, received: .text(text))
		}
		webSocket.onBinary { (ws, buf) in
			await inv.webSocket(ws, on: self, received: .binary(buf))
		}
	}

	public func next() async -> HTTPResponse {
		guard let endpoint else {
			return .error(WrapError(.internal, "call next() but not from serve(webSocket:)"))
		}
		if let mw = await nextMiddleware() {
			let res: HTTPResponse
			do {
				res = try await mw.respond(to: self)
			} catch {
				res = await processDidFailure(error: Errors.internal.convertOrWrap(error, callerSkip: 1), mw, isMiddleware: true)
			}
			await vars.set(lastResponse: res)
			return res
		}
		if await hadJustCalledAllMiddlewares() {
			let res: HTTPResponse
			do {
				switch endpoint.invocation {
				case .request(let inv):
					res = try await inv.respond(to: self)
				case .webSocket(let inv):
					guard let webSocket = await webSocket() else {
						throw WrapError(.internal, "call next() last time but not from serve(webSocket:)")
					}
					try await inv.webSocketDidConnect(webSocket, on: self)
					res = .empty(.ok)
				}
			} catch {
				let inv: Invocation
				switch endpoint.invocation {
				case .request(let it):
					inv = it
				case .webSocket(let it):
					inv = it
				}
				let err = Errors.internal.convertOrWrap(error, callerSkip: 1)
				res = await processDidFailure(error: err, inv, isMiddleware: false)
			}
			await vars.set(lastResponse: res)
			return res
		}
		return await vars.lastResponse
		?? .error(WrapError(.not_found, "\(endpoint.name) no result"))
	}

	private func processDidFailure(
		error: WrapError,
		_ invocation: Invocation,
		isMiddleware: Bool
	) async -> HTTPResponse {
		let wrapped = WrappedRequestError(error: error, invocation: invocation, isMiddleware: isMiddleware)
		await set(wrapped)
		return .error(wrapped.error)
	}

	func close(webSocket: WebSocket, response: HTTPResponse) async {
		var bytes = response.bytes
		let data = bytes.readString(length: bytes.readableBytes) ?? ""
		try? await webSocket.send(data)
		try? await webSocket.close(code: .goingAway)
	}

	func hadJustCalledAllMiddlewares() async -> Bool {
		await vars.middlewareCallIndex == (endpoint?.middlewares.count ?? 0)
	}

	func nextMiddleware() async -> RequestInvocation? {
		let mws = endpoint?.middlewares ?? []
		let mwIndex = await vars.increaseMiddlewareCallIndex()
		return mwIndex < mws.count ? mws[mwIndex] : nil
	}
}

struct WrappedRequestError {
	var error: WrapError
	var invocation: Invocation
	var isMiddleware: Bool
}
