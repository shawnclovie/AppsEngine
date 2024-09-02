//
//  SystemInfo.swift
//
//  Created by Shawn Clovie on 21/3/2022.
//

import Foundation

public func observeSignal(_ signals: Int32..., invoke: @escaping (_ sig: Int32) -> Void) {
	guard !signals.isEmpty else { return }
	let signalQueue = DispatchQueue(label: "signal.observer")
	for sig in signals {
		let source = DispatchSource.makeSignalSource(signal: sig, queue: signalQueue)
		source.setEventHandler {
			invoke(sig)
		}
		source.resume()
	}
}

public struct SystemInfo {
	public let machine: String
	public let nodename: String
	public let release: String
	public let sysname: String
	public let version: String

	public init?() {
		var sysInfo = utsname()
		let result = uname(&sysInfo)
		guard result == EXIT_SUCCESS else { return nil }
		machine = Self.unameField(mirror: .init(reflecting: sysInfo.machine))
		nodename = Self.unameField(mirror: .init(reflecting: sysInfo.nodename))
		release = Self.unameField(mirror: .init(reflecting: sysInfo.release))
		sysname = Self.unameField(mirror: .init(reflecting: sysInfo.sysname))
		version = Self.unameField(mirror: .init(reflecting: sysInfo.version))
	}

	public var isArm: Bool {
		machine.contains("arm") || machine.contains("aarch")
	}

	static func unameField(mirror: Mirror) -> String {
		mirror.children.reduce("") { identifier, element in
			guard let value = element.value as? Int8, value != 0
			else {return identifier}
			return identifier + String(UnicodeScalar(UInt8(value)))
		}
	}
}
