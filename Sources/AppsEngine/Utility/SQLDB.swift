//
//  SQLDB.swift
//  
//
//  Created by Shawn Clovie on 12/10/2022.
//

import Atomics
import Foundation
import FluentKit
import SQLKit

public protocol SQLModel: Codable, Sendable {
	static var schema: String { get }
}

public struct SQLID: RawRepresentable,
					 CustomStringConvertible,
					 Hashable,
					 Codable,
					 JSONEncodable,
					 SQLExpression {
	public static var empty: Self { .init(rawValue: "") }
	
	public typealias RawValue = String

	public var rawValue: RawValue
	
	public init(rawValue: RawValue) {
		self.rawValue = rawValue
	}
	
	public init?(from json: JSON) {
		guard let s = json.stringValue else {
			return nil
		}
		self.init(rawValue: s)
	}

	public init(from decoder: Decoder) throws {
		let text = try decoder.singleValueContainer().decode(RawValue.self)
		self.init(rawValue: text)
	}

	public func encode(to encoder: Encoder) throws {
		var container = encoder.singleValueContainer()
		try container.encode(rawValue)
	}
	
	public func serialize(to serializer: inout SQLSerializer) {
		serializer.write(bind: rawValue)
	}
	
	public var description: String { rawValue }
	
	public var jsonValue: JSON { .string(rawValue) }
}

public struct SQLDB {
	@inlinable
	public static var null: SQLRaw { SQLRaw("NULL") }

	public let instance: Database
	public let executor: SQLDatabase

	public init(instance: Database) throws {
		guard let exec = instance as? SQLDatabase else {
			throw WrapError(.internal, "\(instance) is not SQLDatabase")
		}
		self.init(instance: instance, executor: exec)
	}
	
	public init(instance: Database, executor: SQLDatabase) {
		self.instance = instance
		self.executor = executor
	}

	public func transaction<T>(_ closure: @escaping @Sendable (SQLDB) async throws -> T) async throws -> T {
		try await instance.transaction { db in
			try await closure(SQLDB(instance: db))
		}
	}
	
	public func selectCount(
		from schema: String,
		_ op: ((SQLSelectBuilder) -> Void)? = nil,
		function: String = #function
	) async throws -> Int {
		let q = executor.select().column(SQLRaw("COUNT(*) as c")).from(schema)
		if let op {
			op(q)
		}
		do {
			guard let row = try await q.first() else {
				return 0
			}
			return try row.decode(column: "c")
		} catch {
			throw wrap(error: error, query: q, callFunc: function)
		}
	}

	public func selectFirst<T: SQLModel>(
		columns: [String] = ["*"],
		_ op: ((SQLSelectBuilder) -> Void)? = nil,
		function: String = #function
	) async throws -> T? {
		let q = select(columns: columns, from: T.schema, limit: 1, op)
		do {
			return try await q.first(decoding: T.self)
		} catch {
			throw wrap(error: error, query: q, callFunc: function)
		}
	}

	public func selectFirst<T: SQLModel>(_ q: SQLSelectBuilder, function: String = #function) async throws -> T? {
		do {
			return try await q.first(decoding: T.self)
		} catch {
			throw wrap(error: error, query: q, callFunc: function)
		}
	}

	public func selectAll(_ q: SQLSelectBuilder, function: String = #function) async throws -> [SQLRow] {
		do {
			return try await q.all()
		} catch {
			throw wrap(error: error, query: q, callFunc: function)
		}
	}

	public func selectAll<T: SQLModel>(_ q: SQLSelectBuilder, function: String = #function) async throws -> [T] {
		do {
			return try await q.all(decoding: T.self)
		} catch {
			throw wrap(error: error, query: q, callFunc: function)
		}
	}

	public func selectAll(
		columns: [String] = ["*"],
		from schema: String,
		orderBy: [(String, SQLDirection)]? = nil,
		offset: Int? = nil,
		limit: Int? = nil,
		_ op: ((SQLSelectBuilder) -> Void)? = nil,
		function: String = #function
	) async throws -> [SQLRow] {
		let q = select(columns: columns, from: schema, orderBy: orderBy, offset: offset, limit: limit, op)
		do {
			return try await q.all()
		} catch {
			throw wrap(error: error, query: q, callFunc: function)
		}
	}

	public func selectAll<T: SQLModel>(
		columns: [String] = ["*"],
		orderBy: [(String, SQLDirection)]? = nil,
		offset: Int? = nil,
		limit: Int? = nil,
		_ op: ((SQLSelectBuilder) -> Void)? = nil,
		function: String = #function
	) async throws -> [T] {
		let q = select(columns: columns, from: T.schema, orderBy: orderBy, offset: offset, limit: limit, op)
		do {
			return try await q.all(decoding: T.self)
		} catch {
			throw wrap(error: error, query: q, callFunc: function)
		}
	}

	private func select(
		columns: [String],
		from schema: String,
		orderBy: [(String, SQLDirection)]? = nil,
		offset: Int? = nil,
		limit: Int? = nil,
		_ op: ((SQLSelectBuilder) -> Void)? = nil
	) -> SQLSelectBuilder {
		let query = executor.select().columns(columns).from(schema)
		if let op {
			op(query)
		}
		if let offset {
			query.offset(offset)
		}
		if let limit {
			query.limit(limit)
		}
		if let orderBy, !orderBy.isEmpty {
			for by in orderBy {
				query.orderBy(SQLOrderBy(expression: SQLColumn(by.0), direction: by.1))
			}
		}
		return query
	}

	@discardableResult
	public func insert<T: SQLModel>(
		model: T,
		prefix: String? = nil,
		keyEncodingStrategy: SQLQueryEncoder.KeyEncodingStrategy = .useDefaultKeys,
		nilEncodingStrategy: SQLQueryEncoder.NilEncodingStrategy = .asNil,
		_ op: ((SQLInsertBuilder) -> Void)? = nil,
		onRow: (@Sendable (SQLRow) -> Void)? = nil,
		function: String = #function
	) async throws -> SQLResult {
		try await insert(models: [model],
						 prefix: prefix,
						 keyEncodingStrategy: keyEncodingStrategy,
						 nilEncodingStrategy: nilEncodingStrategy,
						 op, onRow: onRow, function: function)
	}
	
	@discardableResult
	public func insert<T: SQLModel>(
		models: [T],
		prefix: String? = nil,
		keyEncodingStrategy: SQLQueryEncoder.KeyEncodingStrategy = .useDefaultKeys,
		nilEncodingStrategy: SQLQueryEncoder.NilEncodingStrategy = .asNil,
		_ op: ((SQLInsertBuilder) -> Void)? = nil,
		onRow: (@Sendable (SQLRow) -> Void)? = nil,
		function: String = #function
	) async throws -> SQLResult {
		let q = executor.insert(into: T.schema)
		do {
			try q.models(models, prefix: prefix, keyEncodingStrategy: keyEncodingStrategy, nilEncodingStrategy: nilEncodingStrategy)
		} catch {
			throw wrap(error: error, query: q, callFunc: function)
		}
		op?(q)
		return try await execute(q, callFunc: function, onRow: onRow)
	}
	
	@discardableResult
	public func update(
		from schema: String,
		_ op: ((SQLUpdateBuilder) throws -> Void),
		onRow: (@Sendable (SQLRow) -> Void)? = nil,
		function: String = #function
	) async throws -> SQLResult {
		let q = executor.update(schema)
		do {
			try op(q)
		} catch {
			throw wrap(error: error, query: q, callFunc: function)
		}
		return try await execute(q, callFunc: function, onRow: onRow)
	}

	/// UPDATE model.
	/// - Parameters:
	///   - model: Model to update.
	///   - columns: Columns in table to update.
	///     - `nil` or `[]`: `SET` all from `model`
	///     - DO NOT INSERT `*` INSIDE.
	///     - Rest columns would be encoded but table fields wont be updated.
	///   - op: Operation e.g. `whereEq`
	@discardableResult
	public func update<T: SQLModel>(
		model: T,
		columns: Set<String>? = nil,
		_ op: ((SQLUpdateBuilder) -> Void),
		onRow: (@Sendable (SQLRow) -> Void)? = nil,
		function: String = #function
	) async throws -> SQLResult {
		try await update(from: T.schema, {
			if let columns, !columns.isEmpty {
				_ = try SQLQueryEncoder().encode(model).reduce($0) { query, pair in
					columns.contains(pair.0)
					? query.set(SQLColumn(pair.0), to: pair.1)
					: query
				}
			} else {
				try $0.set(model: model)
			}
			op($0)
		}, onRow: onRow, function: function)
	}

	@discardableResult
	public func delete(
		from schema: String,
		_ op: (SQLDeleteBuilder) -> Void,
		onRow: (@Sendable (SQLRow) -> Void)? = nil,
		function: String = #function
	) async throws -> SQLResult {
		let q = executor.delete(from: schema)
		op(q)
		return try await execute(q, callFunc: function, onRow: onRow)
	}

	@discardableResult
	public func delete<T: SQLModel>(
		for: T.Type,
		_ op: (SQLDeleteBuilder) -> Void,
		onRow: (@Sendable (SQLRow) -> Void)? = nil,
		function: String = #function
	) async throws -> SQLResult {
		try await delete(from: T.schema, op, onRow: onRow, function: function)
	}
	
	private func execute(_ query: some SQLQueryBuilder & SQLReturningBuilder,
						 callFunc: String,
						 onRow: (@Sendable (SQLRow) -> Void)?,
						 function: String = #function
	) async throws -> SQLResult {
		if query.returning == nil {
			_ = query.returning("*")
		}
		do {
			let affectCount = ManagedAtomic(0)
			try await executor.execute(sql: query.query, { row in
				_ = affectCount.wrappingIncrementThenLoad(ordering: .sequentiallyConsistent)
				onRow?(row)
			})
			return .init(affectRows: affectCount.load(ordering: .sequentiallyConsistent))
		} catch {
			throw wrap(error: error, query: query, callerSkip: 1, callFunc: callFunc, function: function)
		}
	}
	
	private func wrap(error: Error,
					  query: SQLQueryBuilder,
					  callerSkip: UInt = 0,
					  callFunc: String,
					  function: String = #function) -> WrapError {
		var s = SQLSerializer(database: executor)
		query.query.serialize(to: &s)
		return WrapError(.database, error, [
			"sql": .string(s.sql),
			"func": .array([.string(callFunc), .string(function)]),
		], callerSkip: 2 + callerSkip, maxStack: 2)
	}

	/// Bind `value` if it is not `SQLExpression`.
	public static func bind(_ value: some Encodable & Sendable) -> SQLExpression {
		value as? SQLExpression ?? SQLBind(value)
	}

	/// Bind `group` if it is not `[any SQLExpression]`.
	public static func bind<T: Encodable & Sendable>(group: [T]) -> SQLExpression {
		if let exprs = group as? [any SQLExpression] {
			return SQLGroupExpression(exprs)
		}
		return SQLBind.group(group)
	}
}

public struct SQLResult {
	public let affectRows: Int
}

extension SQLPredicateBuilder {
	@inlinable
	@discardableResult
	public func whereEq(_ column: String, _ value: Optional<some Encodable & Sendable>) -> Self {
		if let value {
			return self.whereEq(column, value)
		}
		return self.where(column, .is, SQLDB.null)
	}

	@inlinable
	@discardableResult
	public func whereEq(_ column: String, _ value: some Encodable & Sendable) -> Self {
		let expr = value as? SQLExpression ?? SQLBind(value)
		return self.where(column, .equal, expr)
	}
	
	@inlinable
	@discardableResult
	public func whereIn(_ column: String, _ value: any Collection<Encodable & Sendable>) -> Self {
		let expr = SQLGroupExpression(value.map({
			$0 as? SQLExpression ?? SQLBind($0)
		}))
		return self.where(column, .in, expr)
	}
}
