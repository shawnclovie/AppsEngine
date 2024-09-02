@preconcurrency import Foundation
import AsyncHTTPClient
import NIO
import NIOHTTP1
import Vapor

public enum HTTP {
	public enum Header {
		public static let content_type = "content-type"
	}

	public enum ContentType {
		public static let binary = "application/octstream"
		public static let json = "application/json"
		public static let multipart_form_data = "multipart/form-data"
		public static let html = "text/html"
		public static let text = "text/plain"
	}

	static let crlf = "\r\n"
}

public struct HTTPResponse: Sendable {
	public enum Body: Sendable {
		/// Cases
		case none
		case buffer(ByteBuffer)
		case data(Data)
		case dispatchData(DispatchData)
		case staticString(StaticString)
		case string(String)
		case stream(Int, @Sendable (BodyStreamWriter) -> ())
		case asyncStream(Int, @Sendable (AsyncBodyStreamWriter) async throws -> ())
	}

	public var status: HTTPResponseStatus
	public var headers: HTTPHeaders
	public var body: Body

	public var error: Error?
	public var metricCode: Int?
	public var metricKeySuffix: String?
	
	public init(_ status: HTTPResponseStatus, headers: HTTPHeaders? = nil, body: Body = .none, error: Error? = nil) {
		self.status = status
		self.headers = headers ?? .init()
		self.body = body
		self.error = error
	}
	
	public init(response: HTTPClient.Response) {
		self.init(response.status, headers: response.headers, body: response.body.map(Body.buffer) ?? .none)
	}
	
	public var bytes: ByteBuffer {
		var buf = ByteBuffer()
		buf.writeString(status.code.description)
		buf.writeString(" ")
		buf.writeString(status.reasonPhrase)
		buf.writeString(HTTP.crlf)
		for header in headers {
			buf.writeString(header.name)
			buf.writeString(": ")
			buf.writeString(header.value)
			buf.writeString(HTTP.crlf)
		}
		buf.writeString(HTTP.crlf)
		switch body {
		case .none:
			break
		case .buffer(var byteBuffer):
			buf.writeBuffer(&byteBuffer)
		case .data(let data):
			buf.writeData(data)
		case .dispatchData(let dispatchData):
			buf.writeDispatchData(dispatchData)
		case .staticString(let staticString):
			buf.writeStaticString(staticString)
		case .string(let string):
			buf.writeString(string)
		case .stream(_, _):
			break
		case .asyncStream(_, _):
			break
		}
		return buf
	}
	
	public static func binary(_ status: HTTPResponseStatus, headers: HTTPHeaders? = nil, _ body: ByteBuffer) -> Self {
		var headers = headers ?? .init()
		headers.replaceOrAdd(name: HTTP.Header.content_type, value: HTTP.ContentType.binary)
		return .init(status, headers: headers, body: .buffer(body))
	}

	public static func error(headers: HTTPHeaders? = nil, _ error: Error) -> Self {
		var headers = headers ?? .init()
		let err = error as? WrappableError ?? WrapError(.internal, error)
		var body: String
		if headers.contentType ?? .json == .json {
			body = JSON.Encoder().encode([Keys.error: .string(err.description)])
			headers.contentType = .json
		} else {
			body = err.description
			let extra = err.collectExtra()
			if !extra.isEmpty {
				body += "\n"
				body += JSON.object(extra).description
			}
		}
		return .init(err.base.status, headers: headers, body: .string(body), error: error)
	}
	
	public static func empty(_ status: HTTPResponseStatus, headers: HTTPHeaders? = nil) -> Self {
		.init(status, headers: headers, body: .none)
	}
	
	public static func text(_ status: HTTPResponseStatus, headers: HTTPHeaders? = nil, _ text: String) -> Self {
		var headers = headers ?? .init()
		headers.replaceOrAdd(name: HTTP.Header.content_type, value: HTTP.ContentType.text)
		return .init(status, headers: headers, body: .string(text))
	}

	/// Marshal `serializable` as `Data` with `JSONSerialization`.
	///
	/// Only support primative type for `serializable`, any Swift struct may cause runtime error.
	public static func json(
		_ status: HTTPResponseStatus,
		headers: HTTPHeaders? = nil,
		serializable: Any
	) -> Self {
		do {
			let data = try JSONSerialization.data(withJSONObject: serializable)
			return json(status, data: data)
		} catch {
			return .error(headers: headers, WrapError(.internal, error))
		}
	}

	/// Marshal `codable` as `Data` with `JSONEncoder`.
	public static func json<Object>(
		_ status: HTTPResponseStatus,
		headers: HTTPHeaders? = nil,
		_ codable: Object
	) -> Self where Object: Encodable {
		do {
			let data = try JSONEncoder().encode(codable)
			return json(status, data: data)
		} catch {
			return .error(headers: headers, WrapError(.internal, error))
		}
	}

	public static func json(
		_ status: HTTPResponseStatus,
		headers: HTTPHeaders? = nil,
		data: Data
	) -> Self {
		var headers = headers ?? .init()
		headers.contentType = .json
		return .init(status, headers: headers, body: .data(data))
	}

	public static func stream(
		_ status: HTTPResponseStatus,
		headers: HTTPHeaders? = nil,
		count: Int = -1,
		_ fn: @escaping @Sendable (any BodyStreamWriter) -> Void
	) -> Self {
		return .init(status, headers: headers, body: .stream(count, fn))
	}
	
	/// - Parameters:
	///   - count: Total data length
	public static func stream(
		_ status: HTTPResponseStatus,
		headers: HTTPHeaders? = nil,
		count: Int = -1,
		_ fn: @escaping @Sendable (any AsyncBodyStreamWriter) async throws -> Void
	) -> Self {
		return .init(status, headers: headers, body: Body.asyncStream(count, fn))
	}

	public static func redirect(_ location: String, temporary: Bool) -> Self {
		var inst = Self(temporary ? .temporaryRedirect : .permanentRedirect)
		inst.headers.replaceOrAdd(name: .location, value: location)
		return inst
	}
}

/// For Vapor
extension HTTPResponse: ResponseEncodable, AsyncResponseEncodable {
	public func encodeResponse(for request: Vapor.Request) async throws -> Vapor.Response {
		response
	}

	public func encodeResponse(for request: Vapor.Request) -> NIOCore.EventLoopFuture<Vapor.Response> {
		request.eventLoop.makeSucceededFuture(response)
	}

	init(response: Response) {
		self.init(response.status, headers: response.headers, body: response.body.buffer.map(Body.buffer) ?? .none)
	}

	var response: Response {
		let respBody: Response.Body = switch body {
		case .none:
				.empty
		case .buffer(let buf):
				.init(buffer: buf)
		case .data(let v):
				.init(data: v)
		case .dispatchData(let v):
				.init(dispatchData: v)
		case .staticString(let v):
				.init(staticString: v)
		case .string(let v):
				.init(string: v)
		case .stream(let count, let callback):
				.init(stream: callback, count: count)
		case .asyncStream(let count, let callback):
				.init(asyncStream: callback, count: count)
		}
		return .init(status: status, headers: headers, body: respBody)
	}
}
