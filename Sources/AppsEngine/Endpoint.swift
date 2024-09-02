//
//  Endpoint.swift
//  
//
//  Created by Shawn Clovie on 22/6/2022.
//

import Foundation
import Vapor

public protocol EndpointProducer: Sendable {
	var name: String { get }
	var routes: [Endpoint.Route] { get }
	var invocation: Endpoint.Invocation { get }
	var middlewares: [EndpointMiddleware] { get }
}

extension EndpointProducer {
	public var endpoint: Endpoint {
		.init(routes, name: name, invocation, middlewares: middlewares)
	}

	public var name: String { routes.isEmpty ? "" : routes[0].name }

	public var middlewares: [EndpointMiddleware] { [] }
}

public struct Endpoint: EndpointProducer {
	public enum Invocation: Sendable {
		case request(RequestInvocation)
		case webSocket(WebSocketInvocation)
	}
	
	public let name: String
	public let routes: [Route]
	public let invocation: Invocation
	public let middlewares: [EndpointMiddleware]

	public init(_ route: Route,
				name: String? = nil,
				_ fn: @escaping RequestClosure,
				middlewares: [EndpointMiddleware] = []) {
		self.init([route], name: name, .request(ClosureRequestInvocation(fn)), middlewares: middlewares)
	}

	public init(_ routes: [Route],
				name: String? = nil,
				_ fn: @escaping RequestClosure,
				middlewares: [EndpointMiddleware] = []) {
		self.init(routes, name: name, .request(ClosureRequestInvocation(fn)), middlewares: middlewares)
	}

	public init(websocket paths: [Route.Component],
				name: String? = nil,
				_ invocation: WebSocketInvocation,
				middlewares: [EndpointMiddleware] = []) {
		self.init([.init(.CONNECT, paths)], name: name, .webSocket(invocation), middlewares: middlewares)
	}

	public init(_ name: String, _ methods: HTTPMethod..., path: String,
				_ fn: @escaping RequestClosure,
				middlewares: [EndpointMiddleware] = []) {
		let paths = path
			.split(separator: PathComponents.urlSeparatorCharacter)
			.map(Route.Component.init)
		self.init(methods.map({ .init($0, paths) }), name: name, .request(ClosureRequestInvocation(fn)), middlewares: middlewares)
	}

	public init(_ name: String, _ methods: HTTPMethod..., path: String,
				_ invocation: Invocation,
				middlewares: [EndpointMiddleware] = []) {
		let paths = path
			.split(separator: PathComponents.urlSeparatorCharacter)
			.map(Route.Component.init)
		self.init(methods.map({ .init($0, paths) }), name: name, invocation, middlewares: middlewares)
	}

	public init(_ routes: [Route],
				name: String?,
				_ invocation: Invocation,
				middlewares: [EndpointMiddleware] = []) {
		self.routes = routes
		if let name, !name.isEmpty {
			self.name = name
		} else {
			self.name = routes.isEmpty ? "" : routes[0].name
		}
		self.invocation = invocation
		self.middlewares = middlewares
	}

	public func withMiddlewares(_ mws: EndpointMiddleware...) -> Self {
		.init(routes, name: name, invocation, middlewares: middlewares + mws)
	}

	public func withInvocation(_ inv: Invocation) -> Self {
		.init(routes, name: name, inv, middlewares: middlewares)
	}
}

extension Endpoint {
	public struct Route: Sendable {
		public struct Component: ExpressibleByStringLiteral, LosslessStringConvertible, CustomStringConvertible, Sendable {
			public static func `var`(_ name: String) -> Self {
				.init(stringLiteral: ":\(name)")
			}

			public typealias StringLiteralType = String

			public let name: String

			public init(_ description: String) {
				name = description
			}

			public init(stringLiteral str: String) {
				name = str
			}

			public init(_ s: any StringProtocol) {
				name = s.description
			}

			public var description: String { name }
		}

		public static func get(_ path: String...) -> Self {
			Self(.GET, path.map(Component.init(_:))[...])
		}

		public static func get(_ path: Component...) -> Self {
			Self(.GET, path[...])
		}

		public static func post(_ path: String...) -> Self {
			Self(.POST, path.map(Component.init(_:))[...])
		}

		public static func post(_ path: Component...) -> Self {
			Self(.POST, path[...])
		}

		public static func put(_ path: String...) -> Self {
			Self(.PUT, path.map(Component.init(_:))[...])
		}

		public static func put(_ path: Component...) -> Self {
			Self(.PUT, path[...])
		}

		public static func delete(_ path: String...) -> Self {
			Self(.DELETE, path.map(Component.init(_:))[...])
		}

		public static func delete(_ path: Component...) -> Self {
			Self(.DELETE, path[...])
		}

		public static func connect(_ path: Component...) -> Self {
			Self(.CONNECT, path[...])
		}

		public let method: HTTPMethod
		public let paths: [Component]

		init(_ method: HTTPMethod, _ paths: [Component]) {
			self.method = method
			self.paths = paths.compactMap({ $0.name.isEmpty ? nil : $0 })
		}

		init(_ method: HTTPMethod, _ paths: ArraySlice<Component>) {
			self.init(method, Array(paths))
		}

		var name: String {
			let path = paths.map(\.name).joined(separator: PathComponents.urlSeparator)
			return "\(method)(\(path))"
		}
	}
}

extension Endpoint {
	public struct Group {
		private let endpointPrefix: String
		private let pathPrefix: String
		private var _endpoints: [Endpoint]
		private var middlewares: [EndpointMiddleware]
		
		public init(endpointPrefix: String, pathPrefix: String,
					endpoints: [any EndpointProducer],
					middlewares: [EndpointMiddleware] = []) {
			self.endpointPrefix = endpointPrefix
			self.pathPrefix = pathPrefix
			_endpoints = endpoints.map(\.endpoint)
			self.middlewares = middlewares
		}
		
		public func withMiddlewares(_ mws: EndpointMiddleware...) -> Self {
			var inst = self
			inst.middlewares.append(contentsOf: mws)
			return inst
		}
		
		public mutating func append(_ endpoinds: any EndpointProducer...) {
			_endpoints.append(contentsOf: endpoinds.map(\.endpoint))
		}
		
		public mutating func append(middlewares: EndpointMiddleware...) {
			self.middlewares.append(contentsOf: middlewares)
		}

		public var endpoints: [Endpoint] {
			let epPrefix = endpointPrefix.hasSuffix(".") ? endpointPrefix : "\(endpointPrefix)."
			return _endpoints.map { ep -> Endpoint in
				.init(ep.routes.map({
					.init($0.method, [.init(pathPrefix)] + $0.paths)
				}),
					  name: epPrefix + ep.name,
					  ep.invocation,
					  middlewares: middlewares + ep.middlewares)
			}
		}
	}
	
	public struct Register {
		public internal(set) var endpoints: [Endpoint] = []
		var endpointNames: Set<String> = []
		
		public init() {}
		
		public mutating func register(_ eps: [Endpoint]) throws {
			let newNames = eps.map(\.name)
			let dups = endpointNames.intersection(newNames)
			guard dups.isEmpty else {
				throw WrapError(.forbidden, "duplicate endpoint name")
			}
			endpoints.append(contentsOf: eps)
			for name in newNames {
				endpointNames.insert(name)
			}
		}
	}
}
