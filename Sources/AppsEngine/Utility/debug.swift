import Foundation
#if os(Linux)
import Backtrace
import CBacktrace
#endif

private let callerMark = "Sources\(PathComponents.systemPathSeparator)"

@inline(__always)
/// Combine caller's file, line and function.
public func caller(file: String = #file, line: Int = #line, function: String = #function) -> String {
	var file = file[...]
	if let range = file.range(of: callerMark) {
		file = file[range.upperBound...]
	}
	return "\(file)#\(line) \(function)"
}

extension Optional where Wrapped == CallerStack {
	public static func capture(skip: UInt = 0, max: UInt = 0) -> Self {
		CallerStack.capture(skip: 1 + skip, max: max)
	}
}

public struct CallerStack: CustomStringConvertible {
	public static func capture(skip: UInt = 0, max: UInt = 0) -> Self {
		let frames = captureRaw(max: max + skip + 1).dropFirst(1 + Int(skip))
		return .init(rawFrames: .init(frames))
	}

	#if os(Linux)
	private static let state = backtrace_create_state(CommandLine.arguments[0], /* supportThreading: */ 1, nil, nil)
	#endif

	static func captureRaw(max: UInt) -> [RawFrame] {
		#if os(Linux)
		final class Context {
			var frames: [RawFrame] = []
			var count: UInt = 0
			let max: UInt
			init(max: UInt) {
				self.max = max
			}
		}
		var context = Context(max: max)
		backtrace_full(state, /* skip: */ 1, { data, pc, filename, lineno, function in
			let frame = RawFrame(
				file: filename.flatMap { String(cString: $0) } ?? "unknown",
				mangledFunction: function.flatMap { String(cString: $0) } ?? "unknown"
			)
			let ctx = data!.assumingMemoryBound(to: Context.self).pointee
			ctx.frames.append(frame)
			ctx.count += 1
			return ctx.count < ctx.max ? 0 : 1 // 0 to continue
		}, { _, cMessage, _ in
			let message = cMessage.flatMap { String(cString: $0) } ?? "unknown"
			fatalError("Failed to capture Linux stacktrace: \(message)")
		}, &context)
		return context.frames
		#else
		var lines = Thread.callStackSymbols.dropFirst(1)
		if max > 0 {
			lines = lines[..<min(Int(max + 1), lines.count)]
		}
		return lines.map { line in
			let parts = line.split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true)
			let file = String(parts[1])
			let funcParts = parts[3].split(separator: "+")
			let mangledFunction = String(funcParts[0]).trimmingCharacters(in: .whitespaces)
			return .init(file: file, mangledFunction: mangledFunction)
		}
		#endif
	}

	public struct Frame: CustomStringConvertible {
		public var file: String
		public var function: String
		
		public var description: String { "\(file) \(function)" }
	}

	public var frames: [Frame] {
		rawFrames.map {
			Frame(file: $0.file, function: _stdlib_demangleName($0.mangledFunction))
		}
	}

	struct RawFrame {
		var file: String
		var mangledFunction: String
	}

	let rawFrames: [RawFrame]

	public func description(max: Int = 16) -> String {
		frames[..<min(frames.count, max)].readable
	}
	
	public var description: String { description() }
}

extension Collection where Element == CallerStack.Frame {
	var readable: String {
		let maxIndexWidth = String(count).count
		let maxFileWidth = map { $0.file.count }.max() ?? 0
		return self.enumerated().map { (i, frame) in
			let indexPad = String(
				repeating: " ",
				count: maxIndexWidth - String(i).count
			)
			let filePad = String(
				repeating: " ",
				count: maxFileWidth - frame.file.count
			)
			return "\(i)\(indexPad) \(frame.file)\(filePad) \(frame.function)"
		}.joined(separator: "\n")
	}
}

/// Here be dragons! _stdlib_demangleImpl is linked into the stdlib. Use at your own risk!
@_silgen_name("swift_demangle")
private func _stdlib_demangleImpl(
	mangledName: UnsafePointer<CChar>?,
	mangledNameLength: UInt,
	outputBuffer: UnsafeMutablePointer<CChar>?,
	outputBufferSize: UnsafeMutablePointer<UInt>?,
	flags: UInt32
) -> UnsafeMutablePointer<CChar>?

private func _stdlib_demangleName(_ mangledName: String) -> String {
	return mangledName.utf8CString.withUnsafeBufferPointer { (mangledUTF8CStr) in
		guard let demangledPtr = _stdlib_demangleImpl(
			mangledName: mangledUTF8CStr.baseAddress,
			mangledNameLength: UInt(mangledUTF8CStr.count - 1),
			outputBuffer: nil,
			outputBufferSize: nil,
			flags: 0)
		else { return mangledName }
		let demangled = String(cString: demangledPtr)
		free(demangledPtr)
		return demangled
	}
}

/// backtrace is included on macOS and Linux, with the same ABI.
@_silgen_name("backtrace")
private func backtrace(_: UnsafeMutablePointer<UnsafeMutableRawPointer?>!, _: UInt32) -> UInt32

public struct DebugFeatures: RawRepresentable, Sendable {
	public var rawValue: String
	
	public init(rawValue: String) {
		self.rawValue = rawValue
	}
}
