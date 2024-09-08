import Foundation
import Algorithms

public struct PathComponents: Equatable, Sendable {
	public static let urlSeparator = "/"
	public static let urlSeparatorCharacter: Character = "/"

	#if os(Windows)
	public static let systemPathSeparator = "\\"
	#else
	public static let systemPathSeparator = "/"
	#endif
	
	@inlinable
	public static func dot(startsWithSeparator: Bool = false, _ comps: String?...) -> Self {
		.init(separator: ".", startsWithSeparator: startsWithSeparator, components: comps.compacted())
	}

	@inlinable
	public static func url(_ comps: String?...) -> Self {
		.init(separator: urlSeparator, components: comps.compacted())
	}

	@inlinable
	public static func urlRoot(_ comps: String?...) -> Self {
		.init(separator: urlSeparator, startsWithSeparator: true, components: comps.compacted())
	}

	@inlinable
	public static func systemPath(_ comps: String?...) -> Self {
		.init(separator: systemPathSeparator, components: comps.compacted())
	}

	@inlinable
	public static func systemAbsolutePath(_ comps: String?...) -> Self {
		.init(separator: systemPathSeparator, startsWithSeparator: true, components: comps.compacted())
	}

	public private(set) var separator: String
	public private(set) var startsWithSeparator: Bool
	public private(set) var components: [String]
	
	public init(separator: String, startsWithSeparator: Bool? = nil, _ comps: String?...) {
		self.init(separator: separator, startsWithSeparator: startsWithSeparator, components: comps.compacted())
	}

	public init(separator: String, startsWithSeparator: Bool? = nil, components: any Collection<String>) {
		self.separator = separator
		self.components = []
		self.startsWithSeparator = startsWithSeparator ?? components.first?.hasPrefix(separator) ?? false
		append(components)
	}

	public var first: String? {
		components.isEmpty ? nil : components[0]
	}

	public var last: String? {
		components.isEmpty ? nil : components[components.count - 1]
	}

	public var count: Int {
		components.count
	}

	public var isEmpty: Bool {
		components.isEmpty
	}
	
	public func with(separator: String) -> Self {
		var inst = self
		inst.separator = separator
		return inst
	}

	@inlinable
	public func appending(_ comps: String?...) -> Self {
		var inst = self
		inst.append(comps[...])
		return inst
	}
	
	@inlinable
	public mutating func append(_ comps: String?...) {
		append(comps[...])
	}

	@inlinable
	public mutating func append(_ comps: ArraySlice<String?>) {
		append(comps.compactMap {
			guard let v = $0 else {
				return nil
			}
			return v.isEmpty ? nil : v
		}[...])
	}

	public mutating func append(_ comps: any Collection<String>) {
		for comp in comps {
			if comp.contains(separator) {
				components.append(contentsOf: comp.components(separatedBy: .init(charactersIn: separator)))
			} else {
				components.append(comp)
			}
		}
	}

	public mutating func append(extension ext: String) {
		guard !ext.isEmpty else {
			return
		}
		if var last = components.last {
			let ext = ext.trimmingCharacters(in: .init(charactersIn: "."))
			if !last.hasSuffix(".") {
				last.append(".")
			}
			last.append(ext)
			components[components.count - 1] = last
		} else {
			let ext = ext.hasPrefix(".") ? ext : ".\(ext)"
			components.append(ext)
		}
	}

	/// Insert `component` at location.
	///
	/// Different with Array's insert, `component` would be -
	/// - insert at 0 on `at` < 0
	/// - append at the end on `at` >= count of `components`
	public mutating func insert(_ component: String, at: Int) {
		guard !component.isEmpty else {
			return
		}
		let at = max(0, at)
		if at >= components.count {
			components.append(component)
		} else {
			components.insert(component, at: at)
		}
	}

	public mutating func removeFirst(_ count: Int = 1) {
		guard !components.isEmpty && count != 0 else {
			return
		}
		if count > components.count {
			components.removeAll()
		} else {
			components.removeFirst(count)
		}
	}
	
	public mutating func removeLast(_ count: Int = 1) {
		guard !components.isEmpty && count != 0 else {
			return
		}
		if count > components.count {
			components.removeAll()
		} else {
			components.removeLast(count)
		}
	}

	public func removingFirst(_ count: Int = 1) -> Self {
		var inst = self
		inst.removeFirst(count)
		return inst
	}

	public func removingLast(_ count: Int = 1) -> Self {
		var inst = self
		inst.removeLast(count)
		return inst
	}

	public mutating func removeAll() {
		components.removeAll()
	}

	public func joined(withOtherSeparator: String? = nil) -> String {
		let count = components.count
		if count == 0 {
			return ""
		} else if count == 1 {
			return components[0]
		} else if separator.isEmpty {
			return components.compactMap { $0 }.joined()
		}
		let separator = withOtherSeparator ?? self.separator
		var lastPath = components[0]
		var buf = ""
		buf.reserveCapacity(128)
		if startsWithSeparator {
			buf.append(separator)
		}
		if !lastPath.isEmpty {
			buf.append(lastPath)
		}
		for i in 1..<count {
			let comp = components[i]
			guard !comp.isEmpty else {
				continue
			}
			let hasSuffix = lastPath.hasSuffix(separator)
			let hasPrefix = comp.hasPrefix(separator)
			if hasSuffix && hasPrefix {
				buf.append(contentsOf: comp.dropFirst(separator.count))
			} else {
				if !lastPath.isEmpty && !hasSuffix && !hasPrefix {
					buf.append(separator)
				}
				buf.append(comp)
			}
			lastPath = comp
		}
		return buf
	}
	
	/// Find last component(s) from `path` with `separator` in `step` (default once).
	///
	/// - Returns
	///   - no `separator` found: whole `path`
	///     - `(path: "a.txt", separator: "/")` -> `"a.txt"`
	///   - found enough times for `step`: rest `path`
	///     - `(path: "f/b/a.txt", separator: "/", step: 2)` -> `"b/a.txt"`
	///   - not enough times for `step`: whole `path`
	///     - `(path: "f/b/a.txt", separator: "/", step: 4)` -> `"b/a.txt"`
	public static func lastComponent(path: String, separator: String, step: UInt = 1) -> Substring {
		var _path = path[...]
		var _step: UInt = 0
		while _step < step && _path.endIndex > path.startIndex {
			let searchingEnd = _step > 0 ? _path.index(before: _path.endIndex) : _path.endIndex
			let searching = _path.startIndex..<searchingEnd
			guard let found = _path.range(of: separator, options: [.backwards], range: searching) else {
				break
			}
			_path = _path[...found.lowerBound]
			_step += 1
		}
		// not found
		if _step == 0 {
			return path[...]
		}
		// found all steps
		if _step == step {
			return path[_path.endIndex...]
		}
		// found some step but not all
		return path[...]
	}
	
	public static func lastComponentURLSeparated(path: String, step: UInt = 1) -> Substring {
		lastComponent(path: path, separator: urlSeparator, step: step)
	}

	public static func lastComponentSystemPathSeparated(path: String, step: UInt = 1) -> Substring {
		lastComponent(path: path, separator: systemPathSeparator, step: step)
	}
}

extension PathComponents {
	public static func ==(_ lhs: Self, _ rhs: Self) -> Bool {
		lhs.separator == rhs.separator
		&& lhs.startsWithSeparator == rhs.startsWithSeparator
		&& lhs.components == rhs.components
	}

	public static func ==(_ lhs: Self, _ rhs: ArraySlice<String?>) -> Bool {
		lhs.components == rhs.compactMap({ $0 })
	}

	public static func ==(_ lhs: Self, _ rhs: [String?]) -> Bool {
		lhs == rhs[...]
	}

	public static func ==(_ lhs: Self, _ rhs: [String]) -> Bool {
		lhs.components == rhs
	}

	public static func +(_ lhs: Self, _ rhs: Self) -> Self {
		var inst = lhs
		inst.append(rhs.components[...])
		return inst
	}

	public static func +(_ lhs: Self, _ comps: [String?]) -> Self {
		var inst = lhs
		inst.append(comps[...])
		return inst
	}

	public static func +=(_ lhs: inout Self, _ comp: String) {
		lhs.append(comp)
	}

	public static func +=(_ lhs: inout Self, _ comps: Array<String?>) {
		lhs.append(comps[...])
	}

	public static func +=(_ lhs: inout Self, _ rhs: Self) {
		lhs.append(rhs.components[...])
	}

	public subscript(index: Int) -> String? {
		get {
			index >= 0 && index < components.count ? components[index] : nil
		}
		set {
			if index < 0 {
				return
			}
			if let newValue {
				if index < components.count {
					components[index] = newValue
				} else {
					components.append(newValue)
				}
			} else {
				if index < components.count {
					components.remove(at: index)
				}
			}
		}
	}

	public func subpath(start: Int?, end: Int?, closed: Bool) -> Self {
		var inst = self
		let count = inst.components.count
		if let end, end >= 0 {
			if end < count - 1 {
				inst.components.removeSubrange((end + 1)...)
			}
		}
		if let start, start > 0 {
			if start > count - 1 {
				inst.components.removeAll()
			} else {
				inst.components.removeSubrange(..<start)
			}
			inst.startsWithSeparator = false
		}
		return inst
	}

	public subscript(range: ClosedRange<Int>) -> Self {
		subpath(start: range.lowerBound, end: range.upperBound, closed: true)
	}

	public subscript(range: PartialRangeFrom<Int>) -> Self {
		subpath(start: range.lowerBound, end: nil, closed: false)
	}

	public subscript(range: PartialRangeUpTo<Int>) -> Self {
		subpath(start: nil, end: range.upperBound, closed: false)
	}

	public subscript(range: PartialRangeThrough<Int>) -> Self {
		subpath(start: nil, end: range.upperBound, closed: true)
	}

	public subscript(range: Range<Int>) -> Self {
		subpath(start: range.lowerBound, end: range.upperBound, closed: false)
	}

	public subscript(range: UnboundedRange) -> Self {
		self
	}
}

extension PathComponents: CustomStringConvertible, Hashable {
	public var description: String {
		joined()
	}
	
	public func hash(into hasher: inout Hasher) {
		separator.hash(into: &hasher)
		components.hash(into: &hasher)
	}
}
