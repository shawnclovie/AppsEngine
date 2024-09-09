import Foundation
import Metrics
import StatsdClient

public struct Metric: Sendable {
	public struct Config: Sendable {
		public var host: String
		public var port: Int

		public init(host: String, port: Int) {
			self.host = host
			self.port = port
		}
	}

	public var verbose = false

	private var client: StatsdClient
	
	public init(host: String, port: Int) throws {
		self.client = try StatsdClient(host: host, port: port)
		MetricsSystem.bootstrap(client)
	}
	
	/// Metric count with prefix `critical.`.
	public func countCritical(_ label: String, dimensions: [(String, String)] = [], count: Int64 = 1) {
		self.count("critical.\(label)", dimensions: dimensions, count: count)
	}
	
	public func count(_ label: String, dimensions: [(String, String)] = [], count: Int64 = 1) {
		client.makeCounter(label: label, dimensions: dimensions)
			.increment(by: count)
		if verbose {
			print("metric.count", label, count)
		}
	}
	
	public func countDouble(_ label: String, dimensions: [(String, String)] = [], count: Double) {
		client.makeFloatingPointCounter(label: label, dimensions: dimensions)
			.increment(by: count)
		if verbose {
			print("metric.count", label, count)
		}
	}

	public func timer(_ label: String, dimensions: [(String, String)] = [], duration: TimeInterval) {
		let nanos = Int64(duration * TimeInterval(TimeUnit.seconds.scaleFromNanoseconds))
		client.makeTimer(label: label, dimensions: dimensions)
			.recordNanoseconds(nanos)
		if verbose {
			print("metric.timer", label, duration)
		}
	}
	
	public func service(appName: String, label: String, count: Int64, duration: TimeInterval) {
		var prefixes = [""]
		if !appName.isEmpty {
			prefixes.append(appName)
		}
		for prefix in prefixes {
			var key = ""
			if !prefix.isEmpty {
				key.append(prefix)
				key.append(".")
			}
			key.append("service.")
			key.append(label)
			self.count(key, count: count)
			if duration > 0 {
				key.append(".timecost")
				timer(key, duration: duration)
			}
		}
	}

	public func makeServiceCounter(appName: String, label: String, count: Int64 = 1, startTime: Date = Date()) -> ServiceCounter {
		ServiceCounter(appName: appName, label: label, count: count, startTime: startTime, metric: self)
	}

	public struct ServiceCounter {
		public let appName: String
		public let label: String
		public let count: Int64
		public let startTime: Date
		
		let metric: Metric
		
		public func log(suffix: String, success: Bool) {
			let dur = success ? Date().distance(to: startTime) : 0
			let key = suffix.isEmpty ? label : "\(label).\(suffix)"
			metric.service(appName: appName, label: key, count: count, duration: dur)
		}
	}
}
