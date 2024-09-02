//
//  Collection+.swift
//  Spot
//
//  Created by Shawn Clovie on 5/4/16.
//  Copyright © 2016 Shawn Clovie. All rights reserved.
//

import Foundation

extension Dictionary {
	@inlinable
	public func valueForKeys(_ keys: Key...) -> Any? {
		valueForKeys(ArraySlice(keys))
	}
	
	@inlinable
	public func valueForKeys(_ keys: [Key]) -> Any? {
		valueForKeys(ArraySlice(keys))
	}
	
	public func valueForKeys(_ keys: ArraySlice<Key>) -> Any? {
		guard let firstKey = keys.first, let value = self[firstKey] else {
			return nil
		}
		if keys.count == 1 {
			return value
		}
		guard let dict = value as? [Key: Any] else {
			return nil
		}
		return dict.valueForKeys(keys.dropFirst())
	}
}

extension Array {
	/// Safety get element in array at index.
	public func elementAt(_ index: Int) -> Element? {
		indices.contains(index) ? self[index] : nil
	}
}

public final class Ref<T> {
	public var value: T
	
	public init(_ v: T) {
		value = v
	}
}

public actor RefActor<Value> {
	public var value: Value

	public init(_ value: Value) {
		self.value = value
	}

	public func set(_ newValue: Value) {
		value = newValue
	}
}
