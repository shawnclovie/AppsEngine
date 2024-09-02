import Foundation
import NIO

public actor TCPClient: Sendable {

	public struct Config: Sendable {
		public var host: String
		public var port: Int
		public var connectTimeout: TimeDuration
		public var reconnectDelay: TimeDuration

		public init(host: String, port: Int,
					connectTimeout: TimeDuration = .seconds(3),
					reconnectDelay: TimeDuration = .seconds(10)) {
			self.host = host
			self.port = port
			self.connectTimeout = connectTimeout
			self.reconnectDelay = reconnectDelay
		}
	}

	public enum ClientError: Error {
		case notReady
		case cantBind
		case timeout
		case connectionResetByPeer
	}

	private enum State: UInt8, Equatable {
		case initializing
		case connecting
		case connected
		case disconnecting
		case disconnected
	}

	public let group: MultiThreadedEventLoopGroup
	public let config: Config
	private var channel: Channel?
	private var messageHandler: MessageHandler?
	private let logger: Logger?

	private var state = State.initializing

	public init(group: MultiThreadedEventLoopGroup, config: Config, logger: Logger? = nil) {
		self.group = group
		self.config = config
		self.logger = logger
		channel = nil
		state = .initializing
	}

	deinit {
		assert(.disconnected == state)
	}
	
	public func connect() async throws {
		assert(.initializing == state)

		let bootstrap = ClientBootstrap(group: group)
			.channelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
		let handler = MessageHandler(bootstrap: bootstrap, config: config, logger: logger)
		_ = bootstrap.channelInitializer { channel in
			channel.pipeline.addHandlers([handler])
		}

		state = .connecting
		channel = try await bootstrap.connect(host: config.host, port: config.port).get()
		state = .connected
		messageHandler = handler
	}

	public func disconnect() -> EventLoopFuture<Void> {
		guard .connected == state, let channel else {
			return group.next().makeFailedFuture(ClientError.notReady)
		}
		state = .disconnecting
		channel.closeFuture.whenComplete { _ in
			Task {
				await self.set(state: .disconnected)
			}
		}
		channel.close(promise: nil)
		return channel.closeFuture
	}

	public func send(_ data: Data) -> EventLoopFuture<Result<Data, Error>> {
		send(ByteBuffer(data: data))
	}

	public func send(_ buf: ByteBuffer) -> EventLoopFuture<Result<Data, Error>> {
		if .connected != state {
			return group.next().makeFailedFuture(ClientError.notReady)
		}
		guard let channel else {
			return group.next().makeFailedFuture(ClientError.notReady)
		}
		let promise = channel.eventLoop.makePromise(of: Data.self)
		let future = channel.writeAndFlush(buf)
		future.cascadeFailure(to: promise) // if write fails
		return future.flatMap {
			promise.futureResult.map { Result.success($0) }
		}
	}

	private func set(state: State) {
		self.state = state
	}

	private actor Reconnector {
		private var task: RepeatedTask? = nil
		private let bootstrap: ClientBootstrap
		let config: Config
		let logger: Logger?

		init(bootstrap: ClientBootstrap, config: Config, logger: Logger?) {
			self.bootstrap = bootstrap
			self.config = config
			self.logger = logger
		}

		func reconnect(on loop: EventLoop) {
			task = loop.scheduleRepeatedTask(
				initialDelay: .seconds(0),
				delay: .nanoseconds(config.reconnectDelay.nanoseconds)
			) { task in
				Task {
					try await self.reconnect()
				}
			}
		}

		private func reconnect() async throws {
			logger?.log(.debug, "reconnecting")
			_ = try await bootstrap.connect(host: config.host, port: config.port).get()
			logger?.log(.debug, "reconnect: done")
			task?.cancel()
			task = nil
		}
	}

	private actor MessageHandler: ChannelInboundHandler, Sendable {
		public typealias InboundIn = ByteBuffer
		public typealias OutboundOut = ByteBuffer
		typealias OutboundIn = ByteBuffer

		private var numBytes = 0
		private let reconnector: Reconnector

		init(bootstrap: ClientBootstrap, config: Config, logger: Logger?) {
			reconnector = Reconnector(bootstrap: bootstrap, config: config, logger: logger)
		}
		
		func channelInactive(context: ChannelHandlerContext) async {
			await reconnector.reconnect(on: context.eventLoop)
			context.fireChannelInactive()
		}

		nonisolated func channelRead(context: ChannelHandlerContext, data: NIOAny) {
			var buffer = unwrapInboundIn(data)
			let readableBytes = buffer.readableBytes
			if let message = buffer.readString(length: readableBytes) {
				reconnector.logger?.log(.debug, "channelRead", .init("message", message))
			}
		}
		
		nonisolated func errorCaught(context: ChannelHandlerContext, error: Error) {
			reconnector.logger?.log(.warn, "errorCaught", .error(error))

			// As we are not really interested getting notified on success or failure we just pass nil as promise to reduce allocations.
			context.close(promise: nil)
		}
	}
}
