//
//  chan.swift
//
//
//  Created by Shawn Clovie on 21/3/2022.
//

import Foundation

public class Chan<Value> {
	private class Waiter<WaitType> {
		enum Direction {
			case receive
			case send
		}

		let direction: Direction
		var fulfilled = false
		private let sema = DispatchSemaphore(value: 0)

		var value: WaitType? {
			get {
				if direction == .receive {
					fulfilled = true
					sema.signal()
				} else if !fulfilled {
					sema.wait()
				}
				return _value
			}
			set(newValue) {
				_value = newValue
				if direction == .send {
					fulfilled = true
					sema.signal()
				} else if !fulfilled {
					sema.wait()
				}
			}
		}

		var _value: WaitType?

		init(direction: Direction) {
			self.direction = direction
		}
	}

	public let capacity: Int

	private var lock = NSLock()
	private var buffer: [Value?] = []
	private var sendQ: [Waiter<Value>] = []
	private var recvQ: [Waiter<Value>] = []

	public init(buffer: Int) {
		capacity = buffer
	}

	public var count: Int {
		buffer.count
	}

	public func send(value: Value) {
		lock.lock()

		// see if we can immediately pair with a waiting receiver
		if let recvW = removeWaiter(&recvQ) {
			recvW.value = value
			lock.unlock()
			return
		}

		// if not, use the buffer if there's space
		if buffer.count < capacity {
			buffer.append(value)
			lock.unlock()
			return
		}

		// otherwise block until we can send
		let sendW = Waiter<Value>(direction: .send)
		sendQ.append(sendW)
		lock.unlock()
		sendW.value = value
	}

	public func receive() -> Value? {
		lock.lock()

		// see if there's oustanding messages in the buffer
		if buffer.count > 0 {
			let value = buffer.remove(at: 0)

			// unblock waiting senders using buffer
			if let sendW = removeWaiter(&sendQ) {
				buffer.append(sendW.value)
			}

			lock.unlock()
			return value
		}

		// if not, pair with any waiting senders
		if let sendW = removeWaiter(&sendQ) {
			lock.unlock()
			return sendW.value
		}

		// otherwise, block until a message is available
		let recvW = Waiter<Value>(direction: .receive)
		recvQ.append(recvW)
		lock.unlock()

		return recvW.value
	}

	private func removeWaiter(_ waitQ: inout [Waiter<Value>]) -> Waiter<Value>? {
		waitQ.count > 0 ? waitQ.remove(at: 0) : nil
	}
}
