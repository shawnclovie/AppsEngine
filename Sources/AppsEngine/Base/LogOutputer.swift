import Foundation
import Logging
import NIO

public struct LogConsoleOutputer: LogOutputer {
	public enum Stream: String {
		case stdout, stderr
		var stream: FileHandle {
			switch self {
			case .stdout:
				return .standardOutput
			case .stderr:
				return .standardError
			}
		}
	}

	public var minimalLevel: Log.Level
	public let stream: FileHandle

	public init(minimalLevel: Log.Level, _ stream: Stream) {
		self.minimalLevel = minimalLevel
		self.stream = stream.stream
	}

	public func log(_ log: borrowing Log) {
		let data = log.encodeAsData()
		if #available(macOS 10.15.4, *) {
			try? stream.write(contentsOf: data)
			try? stream.write(contentsOf: Self.lf)
		} else {
			stream.write(data)
			stream.write(Self.lf)
		}
	}
	
	private static let lf = Data("\n".utf8)
}

public struct LogLoggingOutputer: LogOutputer {
	public var minimalLevel: Log.Level
	public let logger: Logging.Logger

	public init(minimalLevel: Log.Level, name: String) {
		self.minimalLevel = minimalLevel
		logger = .init(label: name)
	}
	
	public func log(_ log: borrowing Log) {
		var logBuf = log.encodeAsBuffer()
		let detail = logBuf.readString(length: logBuf.readableBytes) ?? ""
		logger.log(level: log.level.loggingLevel, .init(stringLiteral: detail), metadata: nil)
	}
}

private extension Log.Level {
	var loggingLevel: Logging.Logger.Level {
		levelForLogging
	}
}

public struct LogTCPOutputer: LogOutputer {
	public var minimalLevel: Log.Level
	public let client: TCPClient

	public init(minimalLevel: Log.Level, options: TCPClient.Config) async {
		self.minimalLevel = minimalLevel
		client = .init(group: .init(numberOfThreads: 1), config: options)
		do {
			try await client.connect()
		} catch {
			print("\(self) connect failed: \(error)")
		}
	}

	public func log(_ log: borrowing Log) {
		let log = copy log
		Task {
			// FIXME: result cannot received
			_ = await client.send(log.encodeAsBuffer()).map { res in
				switch res {
				case .success(_):
					break
				case .failure(let err):
					print("\(type(of: self)) send failed", err)
				}
			}
		}
	}
}
