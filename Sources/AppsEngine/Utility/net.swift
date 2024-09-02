import Foundation
import NIO

public extension SocketAddress {
	static var zero: Self {
		.init(sockaddr_in())
	}
	
	static func lanAddress() throws -> SocketAddress {
		let ips = try availableAddresses()
		guard let ip = ips.first(where: {$0.ipAddress != "127.0.0.1"}) else {
			throw WrapError(.not_found, "no_local_ip")
		}
		return ip
	}

	static func availableAddresses() throws -> [SocketAddress] {
		var address: [SocketAddress] = []
		var ifaddr: UnsafeMutablePointer<ifaddrs>?
		let ret = getifaddrs(&ifaddr)
		guard ret == 0 else {
			throw AnyError("getifaddrs failed with \(ret)")
		}
		var ptr = ifaddr
		while ptr != nil {
			defer { ptr = ptr?.pointee.ifa_next }
			guard let interface = ptr?.pointee else {
				continue
			}
			let addrFamily = interface.ifa_addr.pointee.sa_family
			guard addrFamily == UInt8(AF_INET) || addrFamily == UInt8(AF_INET6) else {
				continue
			}
			var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
			getnameinfo(
				interface.ifa_addr,
				socklen_t(interface.ifa_addr.pointee.sa_len),
				&hostname,
				socklen_t(hostname.count),
				nil,
				socklen_t(0),
				NI_NUMERICHOST
			)
			do {
				let host = String(cString: hostname)
				let addr = try SocketAddress(ipAddress: host, port: 0)
				if case .v4 = addr {
					address.append(addr)
				}
			} catch {}
		}
		freeifaddrs(ifaddr)
		return address
	}
}

#if os(Linux)
extension sockaddr {
	var sa_len: Int {
		switch Int32(sa_family) {
		case AF_INET: return MemoryLayout<sockaddr_in>.size
		case AF_INET6: return MemoryLayout<sockaddr_in6>.size
		default: return MemoryLayout<sockaddr_storage>.size
		}
	}
}
#endif
