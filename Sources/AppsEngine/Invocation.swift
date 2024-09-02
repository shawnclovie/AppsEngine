//
//  Invocation.swift
//  
//
//  Created by Shawn Clovie on 22/6/2022.
//

import Foundation
import Vapor

public protocol Invocation: Sendable {}

public protocol RequestInvocation: Invocation {
	/// Respond HTTP request with context.
	func respond(to ctx: Context) async throws -> HTTPResponse
}

public protocol WebSocketInvocation: Invocation {
	/// WebSocket connection did connect with context.
	/// - Throws: Any error throws would close the connection.
	func webSocketDidConnect(_ webSocket: WebSocket,
							 on ctx: Context) async throws

	/// WebSocket did receive upstream message that text or binary, or ping or pong.
	func webSocket(_ webSocket: WebSocket, on ctx: Context,
				   received upstream: WebSocketUpStream) async

	/// WebSocket did close.
	/// - Parameters:
	///   - error: Error that nullable.
	func webSocket(_ webSocket: WebSocket, on ctx: Context,
				   didClose error: Error?)
}

public extension WebSocketInvocation {
	func webSocketDidConnect(_ webSocket: WebSocket, on ctx: Context) async throws {}
	
	func webSocket(_ webSocket: WebSocket, on ctx: Context, didClose error: Error?) {}
}

public enum WebSocketUpStream {
	case text(String)
	case binary(ByteBuffer)
	case ping(ByteBuffer)
	case pong(ByteBuffer)
}

public typealias RequestClosure = @Sendable (_ ctx: Context) async throws -> HTTPResponse

public struct ClosureRequestInvocation: RequestInvocation {
	public let function: RequestClosure
	
	public init(_ fn: @escaping RequestClosure) {
		function = fn
	}
	
	public func respond(to ctx: Context) async throws -> HTTPResponse {
		return try await function(ctx)
	}
}

public protocol EndpointMiddleware: RequestInvocation {
	/// Make route system respond these HTTP methods with empty 200 response.
	///
	/// Some client may request route with especial method and same path, like CORS.
	///
	/// Each endpoint with GET would automatically respond HEAD.
	var shadowRouteMethods: [HTTPMethod] { get }
}

extension EndpointMiddleware {
	public var shadowRouteMethods: [HTTPMethod] { [] }
}

public struct ClosureMiddleware: EndpointMiddleware {
	public let function: RequestClosure
	public let shadowRouteMethods: [HTTPMethod]
	
	public init(_ fn: @escaping RequestClosure,
				shadowRouteMethods: [HTTPMethod] = []) {
		function = fn
		self.shadowRouteMethods = shadowRouteMethods
	}
	
	public func respond(to ctx: Context) async throws -> HTTPResponse {
		return try await function(ctx)
	}
}
