import Foundation
import Vapor

public actor EngineApp {
	private let engine: Engine
	public let config: AppConfigSet

	private let routes = Routes()
	private let router: TrieRouter<CachedRoute> = .init()

	/// Server wide middlewares.
	private var middleware: [Middleware] = []
	private var notFoundResponder: Responder = NotFoundResponder()

	init(_ engine: Engine, path: URL) async throws {
		let config = try AppConfig(engine.config, rootPath: path, environment: nil)
		self.init(engine, config: await .init(core: config, modules: engine.modules))
	}

	init(_ engine: Engine, config: AppConfigSet) {
		self.engine = engine
		self.config = config
	}

	public var appID: String { config.core.appID }

	public func writeWarningFileIfNeeded(path: URL) async {
		let warnings = await config.warnings
		if warnings.isEmpty {
			if FileManager.default.fileExists(atPath: path.path) {
				try? FileManager.default.removeItem(at: path)
			}
			return
		}
		engine.config.metric?.count("\(config.core.metricName).app.new_app.warning", count: 1)
		let data = (try? JSONSerialization.data(withJSONObject: warnings, options: [.prettyPrinted]))
		?? Data("\(warnings)".utf8)
		do {
			try FileManager.default.makeExist(directory: path.deletingLastPathComponent())
			try data.write(to: path)
		} catch {
			engine.config.defaultLogger.log(.error, "\(Self.self).writeWarningFile", .error(error))
		}
	}

	func prepare(middlewares: [Middleware], in engine: Engine) async throws {
		var proc = await engine.requestProcessor
		await proc?.prepare(for: self)
		if let opts = config.core.cors {
			middleware.append(CORSMiddleware(configuration: opts.configuration))
		}
		middleware.append(contentsOf: middlewares)
		var endpointReg = Endpoint.Register()
		for mod in engine.modules {
			try endpointReg.register(mod.endpoints)
		}
		let routesToRegister = endpointReg
			.endpoints
			.flatMap({ makeRoutes(endpoint: $0, processor: proc) })
		var logs: [RouteLog] = []
		for route in routesToRegister {
			logs.append(contentsOf: register(route))
		}
		if engine.config.verboseItems.contains(Keys.route) {
			print("\(type(of: self)) register routes:", logs.map(\.description).joined(separator: "\n"), separator: "\n")
		}
		notFoundResponder = middleware.makeResponder(chainingTo: notFoundResponder)
	}

	private func makeRoutes(endpoint: Endpoint, processor: RequestProcessor?) -> [RouteRef] {
		var refs: [RouteRef] = []
		for route in endpoint.routes {
			refs.append(makeRoutes(endpoint: endpoint, route: route, processor: processor))
		}
		return refs
	}

	private func makeRoutes(endpoint: Endpoint, route: Endpoint.Route, processor: RequestProcessor?) -> RouteRef {
		let paths: [PathComponent] = route.paths.flatMap {
			if $0.name.contains(PathComponents.urlSeparatorCharacter) {
				return $0.name
					.split(separator: PathComponents.urlSeparatorCharacter)
					.map({ PathComponent(stringLiteral: String($0)) })
			}
			return [PathComponent(stringLiteral: $0.name)]
		}
		switch endpoint.invocation {
		case .webSocket(_):
			let route = routes.webSocket(paths) { (request, ws) async in
				await self.serve(to: request, webSocket: ws, endpoint: endpoint, processor: processor)
			}.description(endpoint.name)
			return .init(route: route, endpoint: endpoint)
		case .request(_):
			let route = routes.on(route.method, paths, body: .collect) { (request) async in
				await self.serve(to: request, endpoint: endpoint, processor: processor)
			}.description(endpoint.name)
			return .init(route: route, endpoint: endpoint)
		}
	}
}

extension EngineApp {
	private static func environment(from request: Request) -> String? {
		request.storage.get(AppEnvRef.self)?.env
	}
	
	private func serve(to request: Request, webSocket: WebSocket, endpoint: Endpoint, processor: RequestProcessor?) async {
		let env = Self.environment(from: request)
		let ctx = await Context(request: request, endpoint: endpoint, engine, configSet: config, requestProcessor: processor, environment: env)
		await ctx.serve(webSocket: webSocket)
	}

	private func serve(to request: Request, endpoint: Endpoint, processor: RequestProcessor?) async -> HTTPResponse {
		let env = Self.environment(from: request)
		let ctx = await Context(request: request, endpoint: endpoint, self.engine, configSet: self.config, requestProcessor: processor, environment: env)
		var response = await ctx.serve()
		// encode response body if needed
		if !ctx.shouldIgnoreBodyProcess,
		   let processor {
			do {
				response = try processor.processResopnse(ctx, response)
			} catch {
				return HTTPResponse
					.error(Errors.internal.convertOrWrap(error))
			}
		}
		await self.engine.apiMetric?.record(to: ctx, response: response)
		if let err = response.error as? WrapError,
		   [.database, .internal].contains(err.base) {
			ctx.logger.log(.error, "internal_error", .init(Keys.url, request.url), .error(err))
		}
		return response
	}

	private func serveShadowRoute(to request: Request, endpoint: Endpoint) async -> Response {
		let env = Self.environment(from: request)
		let ctx = await Context(request: request, endpoint: endpoint, engine, configSet: config, requestProcessor: nil, environment: env)
		let response = await ctx.serve()
		return response.response
	}
}

extension EngineApp {
	private struct RouteLog: CustomStringConvertible {
		let endpoint: String
		let method: String
		let paths: [PathComponent]
		let shadowed: Bool
		
		var description: String {
			"'\(endpoint)' \(method) \(paths.string) \(paths.map({ $0.description }))\(shadowed ? " (shadowed)" : "")"
		}
	}
	
	private func register(_ ref: RouteRef) -> [RouteLog] {
		// Make a copy of the route to cache middleware chaining.
		let cached = CachedRoute(route: ref,
								 responder: middleware.makeResponder(chainingTo: ref.route.responder),
								 isShadowed: false)
		let paths = ref.nonEmptyPathComponents
		var shadowResponders: [String: Responder] = [:]
		if ref.shouldRegisterShadowHeadRoute {
			shadowResponders[HTTPMethod.HEAD.string] = OKResponder()
		}
		for mw in ref.endpoint.middlewares {
			for method in mw.shadowRouteMethods
			where !ref.endpoint.routes.contains(where: { $0.method == method }) {
				let ep = ref.endpoint.withInvocation(.request(OKResponder()))
				shadowResponders[method.string] = AsyncBasicResponder(closure: { [ep] (request) async in
					await self.serveShadowRoute(to: request, endpoint: ep)
				})
			}
		}
		var logs: [RouteLog] = []
		for (method, responder) in shadowResponders {
			registerShadowRoute(method: .init(rawValue: method), responder: responder, cached: cached, paths: paths)
			logs.append(.init(endpoint: ref.endpoint.name, method: method, paths: paths, shadowed: true))
		}
		logs.append(.init(endpoint: ref.endpoint.name, method: ref.route.method.string, paths: paths, shadowed: false))
		router.register(cached, at: [.constant(ref.route.method.string)] + paths)
		return logs
	}
	
	private func registerShadowRoute(method: HTTPMethod, responder: Responder, cached: CachedRoute, paths: [PathComponent]) {
		let route = cached.route.route
		let shadowed = Vapor.Route(method: method,
			path: route.path,
			responder: middleware.makeResponder(chainingTo: responder),
			requestType: route.requestType,
			responseType: route.responseType)
		let _cached = CachedRoute(
			route: .init(route: shadowed, endpoint: cached.route.endpoint),
			responder: middleware.makeResponder(chainingTo: responder),
			isShadowed: true)
		router.register(_cached, at: [.constant(method.string)] + paths)
	}

	func respond(to request: Request, _ env: AppEnvRef) -> EventLoopFuture<Response> {
		let response: EventLoopFuture<Response>
		if let cachedRoute = getRoute(for: request) {
			request.route = cachedRoute.route.route
			request.storage.set(AppEnvRef.self, to: env)
			response = cachedRoute.responder.respond(to: request)
		} else {
			response = notFoundResponder.respond(to: request)
		}
		return response
	}

	/// Gets a `Route` from the underlying `TrieRouter`.
	private func getRoute(for request: Request) -> CachedRoute? {
		let pathComponents = request.url.path
			.split(separator: PathComponents.urlSeparatorCharacter)
			.map(String.init)
		// If it's a HEAD request and a HEAD route exists, return that route...
		if request.method == .HEAD,
		   let route = router.route(
			path: [HTTPMethod.HEAD.string] + pathComponents,
			parameters: &request.parameters) {
			return route
		}
		// ...otherwise forward HEAD requests to GET route
		let method = (request.method == .HEAD) ? .GET : request.method
		return router.route(
			path: [method.string] + pathComponents,
			parameters: &request.parameters)
	}
}

/// For respond.
private struct CachedRoute {
	let route: RouteRef
	let responder: Responder
	let isShadowed: Bool
}

/// For define relation between `endpoint` and `route`.
private struct RouteRef {
	let route: Vapor.Route
	let endpoint: Endpoint
	
	var name: String { "\(route.method.string) \(endpoint.routes.map(\.name))" }

	/// Remove any empty path components.
	var nonEmptyPathComponents: [PathComponent] {
		route.path.filter { component in
			if case let .constant(string) = component {
				return string != ""
			}
			return true
		}
	}

	/// If the route isn't explicitly a HEAD route and it's made up solely of .constant components,
	/// register a HEAD route with the same path.
	var shouldRegisterShadowHeadRoute: Bool {
		route.method == .GET && route.path.allSatisfy({ component in
			if case .constant = component { return true }
			return false
		})
	}
}

private struct OKResponder: Responder, RequestInvocation {
	func respond(to request: Request) -> EventLoopFuture<Response> {
		request.eventLoop.makeSucceededFuture(.init(status: .ok))
	}
	
	func respond(to ctx: Context) async throws -> HTTPResponse {
		.empty(.ok)
	}
}

private struct NotFoundResponder: Responder {
	var response: HTTPResponse {
		HTTPResponse.error(Errors.route_not_found)
	}

	func respond(to request: Request) -> EventLoopFuture<Response> {
		request.eventLoop.makeSucceededFuture(response.response)
	}
}
