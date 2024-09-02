//
//  DBExecutor.swift
//
//  Created by Shawn Clovie on 28/3/2022.
//

import Foundation
import FluentKit
import FluentMongoDriver
import MongoCore
import MongoKitten
import AppsEngine

public typealias MongoDBType = MongoDatabase

public protocol MongoDBDocumentCodable {
	init(import document: Document) throws

	func exportDocument() -> Document
}

public protocol MongoDBModel: MongoDBDocumentCodable {
	static var schema: String { get }

	var modelID: ObjectId { get }

	func updateWhere() -> Document
}

extension MongoDBModel {
	public func updateWhere() -> Document {
		[Keys._id: modelID]
	}
}

public struct MongoDBExecutor {
	public let db: MongoDatabase
	public let logger: AppsEngine.Logger
	
	public init(db: MongoDatabase, logger: AppsEngine.Logger) {
		self.db = db
		self.logger = logger.with(trace: [.init("module", "\(Self.self)")])
	}
	
	public func runTransaction<Return>(_ exec: (_ db: MongoDBExecutor) async throws -> Return) async throws -> Return {
		let tx = try db.startTransaction(autoCommitChanges: false)
		do {
			let ret = try await exec(.init(db: tx, logger: logger))
			try await tx.commit().get()
			return ret
		} catch {
			try await tx.abort().get()
			throw error
		}
	}
	
	public func count<Model>(for type: Model.Type, _ query: Document?) async -> Result<Int, WrapError>
	where Model: MongoDBModel {
		do {
			let result = try await db[Model.schema].count(query).get()
			return .success(result)
		} catch {
			return .failure(Errors.database.convertOrWrap(error))
		}
	}
	
	public func loadOne<Model>(for type: Model.Type, _ query: Document) async -> Result<Model?, WrapError>
	where Model: MongoDBModel {
		do {
			let result = try await db[Model.schema].findOne(query).get()
			return .success(try result.flatMap(Model.init(import:)))
		} catch {
			return .failure(Errors.database.convertOrWrap(error))
		}
	}

	public func loadMany<Model>(for type: Model.Type,
						 where: Document = [:],
						 sort: [String: Bool]? = nil,
						 project: [String: Bool]? = nil,
						 skip: Int? = nil,
						 limit: Int? = nil) async -> Result<[Model], WrapError>
	where Model: MongoDBModel {
		let result = await loadMany(schema: Model.schema, where: `where`, sort: sort, project: project, skip: skip, limit: limit)
		switch result {
		case .failure(let error):
			return .failure(error)
		case .success(let docs):
			do {
				return .success(try docs.map(Model.init(import:)))
			} catch {
				return .failure(Errors.databasePrimaryDataInvalid.convertOrWrap(error))
			}
		}
	}
	
	/// Load many documents.
	/// - Parameters:
	///   - schema: Collection name
	///   - where: Condition to load
	///   - sort: Sort method, true in value means ascending (1 in mongo shell), false means descending (-1).
	///   - project: Fields in result to load
	///     - `[name: true, _id: false]`: only name in result, and no object id.
	///     - `[name: false]`: all fields but name in result.
	///   - skip: Skipped count, equals OFFSET in SQL.
	///   - limit: Limit count, equals LIMIT in SQL.
	/// - Returns: Result of loaded documents or error.
	public func loadMany(schema: String,
						 where: Document = [:],
						 sort: [String: Bool]? = nil,
						 project: [String: Bool]? = nil,
						 skip: Int? = nil,
						 limit: Int? = nil) async -> Result<[Document], WrapError> {
		do {
			var query = db[schema].find(`where`)
			if let sort = sort, !sort.isEmpty {
				var v = Document()
				for it in sort {
					v[it.key] = it.value ? 1 : -1
				}
				query = query.sort(v)
			}
			if let project = project, !project.isEmpty {
				var v = Projection()
				for it in project {
					if it.value {
						v.include(it.key)
					} else {
						v.exclude(it.key)
					}
				}
				query = query.project(v)
			}
			if let skip = skip {
				query = query.skip(skip)
			}
			if let limit = limit {
				query = query.limit(limit)
			}
			logger.log(.debug, "db.loadMany", .init("table", schema), .init("doc", query))
			let result = try await query.execute().get()
			let docs = try await result.nextBatch()
			return .success(docs)
		} catch {
			return .failure(WrapError(.database, error, maxStack: 2))
		}
	}

	public func insert<Model>(_ model: Model...) async -> MongoExecutionResult
	where Model: MongoDBModel {
		await insert(model)
	}

	public func insert<Model>(_ models: [Model]) async -> MongoExecutionResult
	where Model: MongoDBModel {
		let doc: [Document] = models.map { model in
			var doc = model.exportDocument()
			if doc[Keys._id] == nil {
				doc[Keys._id] = model.modelID
			}
			return doc
		}
		let table = db[Model.schema]
		logger.log(.debug, "db.insert", .init("table", table.name), .init("doc", doc))
		do {
			let result = try await table.insertMany(doc).get()
			return .init(affectCount: result.insertCount,
						 errors: result.writeErrors,
						 concernError: result.writeConcernError)
		} catch {
			return .init(error: error)
		}
	}
	
	/// Update the model with `exportDocument` from it.
	/// - Parameters:
	///   - model: updateing model.
	///   - `where`: update condition, it would be `model.updateWhere()` if the parameter is nil.
	public func update<Model>(_ model: Model, `where`: Document? = nil) async -> MongoExecutionResult
	where Model: MongoDBModel {
		let `where` = `where` ?? model.updateWhere()
		var doc = model.exportDocument()
		if doc[Keys._id] == nil {
			doc[Keys._id] = model.modelID
		}
		let table = db[Model.schema]
		logger.log(.debug, "db.update", .init("table", table.name),
				   .init("doc", doc), .init("where", `where`))
		do {
			let result = try await table.updateOne(where: `where`, to: doc).get()
			return .init(affectCount: result.updatedCount,
						 errors: result.writeErrors,
						 concernError: result.writeConcernError)
		} catch {
			return .init(error: Errors.database.convertOrWrap(error))
		}
	}

	public func update<Model>(for type: Model.Type,
							  set: Document?,
							  unset: Document?,
							  where: Document) async -> MongoExecutionResult
	where Model: MongoDBModel {
		let table = db[Model.schema]
		logger.log(.debug, "db.update_where", .init("table", table.name),
				   .init("set", set as Any), .init("unset", unset as Any),
				   .init("where", `where`))
		do {
			let result = try await table.updateMany(where: `where`, setting: set, unsetting: unset).get()
			return .init(affectCount: result.updatedCount,
						 errors: result.writeErrors,
						 concernError: result.writeConcernError)
		} catch {
			return .init(error: Errors.database.convertOrWrap(error))
		}
	}

	public func delete<Model>(_ model: Model) async -> MongoExecutionResult
	where Model: MongoDBModel {
		await delete(for: Model.self, where: [Keys._id: model.modelID])
	}
	
	public func delete<Model>(for type: Model.Type, where: Document) async -> MongoExecutionResult
	where Model: MongoDBModel {
		do {
			let result = try await db[Model.schema].deleteAll(where: `where`).get()
			return .init(affectCount: result.deletes,
						 errors: result.writeErrors,
						 concernError: result.writeConcernError)
		} catch {
			return .init(error: Errors.database.convertOrWrap(error))
		}
	}
}

public enum MongoDBOp {
	/// Value `in` array.
	public static let `in` = "$in"
	/// Value `not in` array.
	public static let nin = "$nin"
	/// Value `equal` other value.
	public static let eq = "$eq"
	/// Value `greater than` other value.
	public static let gt = "$gt"
	/// Value `greater than or equal` other value.
	public static let gte = "$gte"
	/// Value `less than` other value.
	public static let lt = "$lt"
	/// Value `less than or equal` other value.
	public static let lte = "$lte"
	/// Value `not equal` other value.
	public static let ne = "$ne"
	
	/// Logical `and`.
	public static let and = "$and"
	/// Logical `not`.
	public static let not = "$not"
	/// Logical `not or`.
	public static let nor = "$nor"
	/// Logical `or`.
	public static let or = "$or"
	
	/// Is field `exists` to `Bool`.
	public static let exists = "$exists"
	/// Is field `typed` to `String`
	///
	/// `double`, `string`, `object`, `array`, `binData`, `objectId`, `bool`, `date`, `null`, `regex`, `javascript`, `int` (32-bit), `timestamp`, `long` (64-bit), `decimal`.
	public static let type = "$type"
	
	/// Allows the use of aggregation expressions within the query language.
	///
	/// https://www.mongodb.com/docs/manual/reference/operator/query/expr/
	public static let expr = "$expr"
	/// Matches documents that satisfy the specified JSON Schema.
	public static let jsonSchema = "$jsonSchema"
	/// Is field `mod` to [divisor, remainder].
	public static let mod = "$mod"
	/// Is field `regex` to pattern.
	public static let regex = "$regex"
	/// Options for other op.
	public static let options = "$options"
}

public struct MongoExecutionResult {
	public struct ErrorType: OptionSet {
		public static let constraint = Self(rawValue: 1)
		public static let connectionClosed = Self(rawValue: 2)
		public static let syntax = Self(rawValue: 4)

		public let rawValue: Int8

		public init(rawValue: Int8) {
			self.rawValue = rawValue
		}
	}

	public var affectCount: Int
	public var errors: [Error]
	public var errorTypes: ErrorType

	public init(affectCount: Int, errors: [Error] = [], errorTypes: ErrorType = []) {
		self.affectCount = affectCount
		self.errors = errors
		self.errorTypes = errorTypes
	}

	public var error: WrapError? {
		if errors.isEmpty {
			return nil
		}
		let base = !errorTypes.isEmpty && errorTypes == [.connectionClosed] ? Errors.database_constraint_violation : Errors.database
		return WrapError(base, "\(errors)")
	}

	@discardableResult
	public func get() throws -> Int {
		if let error {
			throw error
		}
		return affectCount
	}
}

extension MongoExecutionResult {
	init(affectCount: Int,
		 errors: [MongoWriteError]?,
		 concernError: WriteConcernError?) {
		var _errors: [Error] = []
		var _errTypes: ErrorType = []
		if let errors = errors {
			_errors = errors
			for err in errors {
				if err.isConnectionClosed {
					_errTypes.insert(.connectionClosed)
				} else if err.isSyntaxError {
					_errTypes.insert(.syntax)
				} else if err.isConstraintFailure {
					_errTypes.insert(.constraint)
				}
			}
		}
		if let concernError = concernError {
			_errors.append(concernError)
		}
		self.init(affectCount: affectCount, errors: _errors, errorTypes: _errTypes)
	}
	
	init(error: Error) {
		self.init(affectCount: 0, errors: [WrapError(.database, error)])
	}
}

extension MongoWriteError: Error {}
extension WriteConcernError: Error {}
