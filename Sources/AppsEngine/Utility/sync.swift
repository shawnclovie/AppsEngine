import Foundation
import Dispatch

public struct SynchronizableValue<Value> {
	private var value: Value
	private let lock: DispatchSemaphore
	
	public init(_ v: Value, maxAccessCount: Int = 1) {
		value = v
		lock = .init(value: max(1, maxAccessCount))
	}
	
	public func get() -> Value { value }
	
	public func waitAndGet() -> Value {
		lock.wait()
		let v = value
		lock.signal()
		return v
	}
	
	public mutating func waitAndSet(_ v: Value) {
		lock.wait()
		value = v
		lock.signal()
	}
	
	public mutating func waitAndSet(_ v: Value, timeout: DispatchTime) throws {
		switch lock.wait(timeout: timeout) {
		case .success:
			value = v
			lock.signal()
		case .timedOut:
			throw Errors.timeout
		}
	}
	
	@discardableResult
	public mutating func waitAndSet<R>(with fn: (inout Value)->R) -> R {
		lock.wait()
		let r = fn(&value)
		lock.signal()
		return r
	}
	
	@discardableResult
	public mutating func waitAndSet<R>(with fn: (inout Value)->R, timeout: DispatchTime) throws -> R {
		switch lock.wait(timeout: timeout) {
		case .success:
			let r = fn(&value)
			lock.signal()
			return r
		case .timedOut:
			throw Errors.timeout
		}
	}
}
