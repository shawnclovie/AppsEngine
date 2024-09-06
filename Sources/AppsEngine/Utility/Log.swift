import Foundation
import Logging
import NIOCore

public protocol LogOutputer: Sendable {
	var level: Log.Level { get set }
	func log(_ log: borrowing Log)
}

public struct LogClosureOutputer: LogOutputer {
	public var level: Log.Level
	public let closure: @Sendable (Log) -> Void

	public init(level: Log.Level, closure: @escaping @Sendable (Log) -> Void) {
		self.level = level
		self.closure = closure
	}

	public func log(_ log: borrowing Log) {
		closure(log)
	}
}

public struct Logger: Sendable {

	public var outputers: [LogOutputer]
	/// Label or Tag
	public let label: String?
	var trace: Trace
	public var metadata = Logging.Logger.Metadata()
	public let timezone: TimeZone?

	public init(label: String? = nil, outputers: [LogOutputer] = [], trace: Trace = Trace(nil, on: .zero), timezone: TimeZone? = nil) {
		self.label = label
		self.outputers = outputers
		self.trace = trace
		self.timezone = timezone
	}
	
	public mutating func append(trace: Trace) {
		self.trace.merge(trace)
	}

	public mutating func setLevelToAllOutputers(_ level: Log.Level) {
		for i in outputers.indices {
			outputers[i].level = level
		}
	}

	public func with(label: String? = nil, concat: Bool = false,
					 trace: Trace? = nil) -> Self {
		.init(label: label.map({ concat ? PathComponents.dot(self.label, $0).joined() : $0 }) ?? self.label,
			  outputers: outputers, trace: trace ?? self.trace, timezone: timezone)
	}
	
	public mutating func append(trace pairs: [Log.Pair]) {
		trace.pairs.append(contentsOf: pairs)
	}
	
	public func with(trace pairs: [Log.Pair]) -> Self {
		var inst = self
		inst.append(trace: pairs)
		return inst
	}

	public func log(_ level: Log.Level, _ subject: String, _ pairs: Log.Pair...,
					file: String = #file, function: String = #function, line: UInt = #line) {
		log(Log(level: level, produce(subject: subject, pairs: pairs, file: file, function: function, line: line), timezone: timezone))
	}

	public func log(_ level: Log.Level, _ subject: String, _ pairs: [Log.Pair],
					file: String = #file, function: String = #function, line: UInt = #line) {
		log(Log(level: level, produce(subject: subject, pairs: pairs, file: file, function: function, line: line), timezone: timezone))
	}

	public func log(_ log: consuming Log) {
		for outputer in marchLevelOutputers(log.level) {
			outputer.log(log)
		}
	}
	
	private func produce(subject: String, pairs: [Log.Pair],
						 file: String, function: String, line: UInt) -> [Log.Pair] {
		var dedup: [String: any Sendable] = [:]
		dedup.reserveCapacity(trace.pairs.count + pairs.count + 1)
		for log in trace.pairs {
			dedup[log.key] = log.value
		}
		if !trace.startTime.isZero {
			dedup[Keys.trace_dur] = TimeDuration.since(trace.startTime).description
		}
		for v in pairs {
			if let exists = dedup[v.key] {
				dedup[v.key] = "\(exists),\(v.value)"
			} else {
				dedup[v.key] = v.value
			}
		}
		var toLog: [Log.Pair] = []
		if let label {
			toLog.append(.init("label", label))
		}
		toLog.append(contentsOf: [Log.Pair](metadata: metadata))
		toLog.reserveCapacity(dedup.count + toLog.count + 2)
		toLog.append(.init("message", subject))
		let file = PathComponents.lastComponentSystemPathSeparated(path: file, step: 2)
		toLog.append(.init("file", "\(file)#\(line)#\(function)"))
		for (k, v) in dedup {
			toLog.append(.init(k, v))
		}
		return toLog
	}
	
	private func marchLevelOutputers(_ level: Log.Level) -> [LogOutputer] {
		var outputers = [LogOutputer]()
		for outputer in self.outputers {
			if level.index.rawValue >= outputer.level.index.rawValue {
				outputers.append(outputer)
			}
		}
		return outputers
	}
	
	public struct Trace: Sendable {
		var startTime: Time
		var pairs: [Log.Pair]
		
		public init(_ traceID: String? = nil, on time: Time, _ pairs: [Log.Pair] = []) {
			startTime = time
			self.pairs = pairs
			if let traceID = traceID {
				self.pairs.append(.init(Keys.trace_id, traceID))
			}
		}

		mutating func merge(_ other: Self) {
			if startTime.isZero {
				startTime = other.startTime
			}
			pairs.append(contentsOf: other.pairs)
		}
	}
}

extension Logger: LogHandler {
	public subscript(metadataKey key: String) -> Logging.Logger.Metadata.Value? {
		get {
			metadata[key]
		}
		set(newValue) {
			if let newValue {
				metadata[key] = newValue
			} else {
				metadata.removeValue(forKey: key)
			}
		}
	}

	public var logLevel: Logging.Logger.Level {
		get {
			outputers.reduce(Log.Level.error) { res, outputer in
				min(res, outputer.level)
			}.levelForLogging
		}
		set(newValue) {
			for i in 0..<outputers.count {
				outputers[i].level = .init(fromLogging: newValue)
			}
		}
	}

	public func log(level: Logging.Logger.Level,
					message: Logging.Logger.Message,
					metadata: Logging.Logger.Metadata?,
					source: String, file: String, function: String, line: UInt) {
		var pairs: [Log.Pair] = metadata.map([Log.Pair].init(metadata:)) ?? []
		pairs.append(.init("source", source))
		log(.init(fromLogging: level), message.description, pairs, file: file, function: function, line: line)
	}
}

public struct Log: Sendable {
	fileprivate enum LevelIndex: UInt8 {
		case trace, debug, info, notice, warn, error, critical
	}

	public enum Level: String, Comparable, Equatable, Sendable {
		public static func < (lhs: Log.Level, rhs: Log.Level) -> Bool {
			lhs.index.rawValue < rhs.index.rawValue
		}
		
		case trace, debug, info, notice, warn, error, critical

		public init(fromLogging level: Logging.Logger.Level) {
			switch level {
			case .trace:	self = .trace
			case .debug:	self = .debug
			case .info:		self = .info
			case .notice:	self = .notice
			case .warning:	self = .warn
			case .error:	self = .error
			case .critical:	self = .critical
			}
		}
		
		fileprivate var index: LevelIndex {
			switch self {
			case .trace:	return .trace
			case .debug:	return .debug
			case .info:		return .info
			case .notice:	return .notice
			case .warn:		return .warn
			case .error:	return .error
			case .critical:	return .critical
			}
		}
		
		public var levelForLogging: Logging.Logger.Level {
			switch self {
			case .trace:	return .trace
			case .debug:	return .debug
			case .info:		return .info
			case .notice:	return .notice
			case .warn:		return .warning
			case .error:	return .error
			case .critical:	return .critical
			}
		}
	}

	public struct Pair: Sendable {
		public static func any(_ key: String, _ value: any Sendable) -> Self {
			.init(key, value)
		}

		public static func error(_ value: any Sendable) -> Self {
			.init(Keys.error, value)
		}
		
		public static func appID(_ value: String) -> Self {
			.init(Keys.app_id, value)
		}
		
		public static func userID(_ value: String) -> Self {
			.init(Keys.user_id, value)
		}
		
		public let key: String
		public let value: any Sendable

		public init(_ key: String, _ value: any Sendable) {
			self.key = key
			self.value = value
		}

		public init(_ tuple: (String, any Sendable)) {
			self.init(tuple.0, tuple.1)
		}
	}

	public let level: Level
	public var pairs: [Pair] = []
	public let time: Time
	public let timezone: TimeZone?

	public init(level: Level, _ pairs: [Pair], timezone: TimeZone?) {
		self.level = level
		self.pairs.append(contentsOf: pairs)
		time = .local
		self.timezone = timezone
	}

	public mutating func append(contentsOf dict: [AnyHashable: Any]) {
		for it in dict {
			pairs.append(.init(it.key as? String ?? it.key.description, "\(it.value)"))
		}
	}
	
	public var allPairs: [Pair] {
		let t = if let timezone {
			time.in(zone: timezone)
		} else {
			time
		}
		var m: [Pair] = [
			.init("time", TimeLayout.rfc3339Millisecond.format(t)),
			.init("level", level.rawValue),
		]
		m.append(contentsOf: pairs)
		return m
	}
	
	public func encodeAsData() -> Data {
		var buf = encodeAsBuffer()
		let data = buf.readData(length: buf.readableBytes)
		return data ?? Data()
	}
	
	public func encodeAsBuffer() -> ByteBuffer {
		let encoder = Encoder()
		return encoder.encode(pairs: allPairs)
	}
	
	private struct Encoder {
		let keyEncoder = JSON.Encoder(options: [.withoutEscapingSlashes])
		let valueEncoder = JSONEncoder()
		
		init() {
			valueEncoder.outputFormatting = [.withoutEscapingSlashes]
		}
		
		func encode(pairs: [Pair]) -> ByteBuffer {
			var buf = ByteBuffer(staticString: JSON.Const.bracketCurlyL)
			var first = true
			for pair in pairs {
				if first {
					first = false
				} else {
					buf.writeStaticString(JSON.Const.comma)
				}
				let key = keyEncoder.encode(.string(pair.key))
				buf.writeString(key)
				buf.writeStaticString(JSON.Const.colon)
				write(value: pair.value, into: &buf)
			}
			buf.writeStaticString(JSON.Const.bracketCurlyR)
			return buf
		}
		
		private func write(value: Any, into buf: inout ByteBuffer) {
			switch value {
			case Optional<Any>.none:
				buf.writeStaticString(JSON.Const.null)
			case let v as Bool:
				buf.writeStaticString(v ? JSON.Const.true : JSON.Const.false)
			case let v as String:
				write(encodable: v, into: &buf)
			case let v as JSON:
				write(encodable: v, into: &buf)
			case let v as CustomDebugStringConvertible:
				write(value: v.debugDescription, into: &buf)
			case let v as Encodable:
				write(encodable: v, into: &buf)
			default:
				let desc = String(reflecting: value)
				write(encodable: desc, into: &buf)
			}
		}
		
		private func write(encodable: any Encodable, into buf: inout ByteBuffer) {
			do {
				let encoded = try valueEncoder.encode(encodable)
				buf.writeData(encoded)
			} catch {
				buf.writeStaticString(JSON.Const.quote)
				buf.writeString(String(describing: encodable))
				buf.writeStaticString(JSON.Const.quote)
			}
		}
	}
}

extension [Log.Pair] {
	public init(metadata: Logging.Logger.Metadata) {
		self.init()
		reserveCapacity(metadata.count)
		for (key, value) in metadata {
			append(.init(key, value.description))
		}
	}
}
