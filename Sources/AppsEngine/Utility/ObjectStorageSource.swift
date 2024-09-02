import Foundation

public struct ObjectStorageCloudSource: Equatable, Sendable {
	public var region: String?
	public var secretID: String
	public var secretKey: String
	public var endpoint: URL?
	
	public init(region: String?,
				secretID: String,
				secretKey: String,
				endpoint: URL?) {
		self.region = region
		self.secretID = secretID
		self.secretKey = secretKey
		self.endpoint = endpoint
	}
	
	public init(_ config: [String: JSON]) {
		region = config[Keys.region]?.stringValue
		secretID = config[Keys.secret_id]?.stringValue ?? ""
		secretKey = config[Keys.secret_key]?.stringValue ?? ""
		endpoint = config[Keys.endpoint]?.stringValue.flatMap(URL.init(string:))
	}
}

public struct ObjectStorageSource: Equatable, Sendable {
	public var name: String?
	public var cloud: ObjectStorageCloudSource
	public var bucket: String
	public var path = PathComponents.url()
	public var baseURL: String?
	
	/// Create Source of ObjectStorage
	/// - Parameters:
	///   - name: Name of the source.
	///   - cloud: Cloud properties.
	///   - path: Path may contains `bucket` and `basepath`, or `bucket` only.
	public init(name: String?, cloud: ObjectStorageCloudSource, path: String, baseURL: String?) throws {
		let paths = Self.split(path: path)
		guard !paths.isEmpty else {
			throw WrapError(.invalid_parameter, "path does not contains bucket")
		}
		self.name = name
		self.cloud = cloud
		self.baseURL = baseURL
		bucket = String(paths[0])
		if paths.count > 1 {
			append(paths: paths.dropFirst())
		}
	}
	
	/// Create with URL string.
	/// - Parameter url: `ENDPOINT/BUCKET/BASEPATH?name=SOURCE&region=REGION&secret=SECRET_ID:SECRET_KEY`
	///
	/// - Example:
	///    - AWS: `/my_bucket?name=aws&region=us-east-1&secret=SECRET_ID:SECRET_KEY`
	///    - OSS: `http://oss-cn-beijing.aliyuncs.com/my_bucket?secret=SECRET_ID:SECRET_KEY`
	public init(urlString: String, baseURL: String?) throws {
		guard let comps = URLComponents(string: urlString) else {
			throw WrapError(.invalid_parameter, "URL format invalid")
		}
		var config: [String: String] = [:]
		for it in comps.queryItems ?? [] where !it.name.isEmpty {
			guard let value = it.value, !value.isEmpty else { continue }
			config[it.name] = value
		}
		let secrets = config[Keys.secret]?.split(separator: ":", maxSplits: 2) ?? []
		let cloud = ObjectStorageCloudSource(
			region: config[Keys.region],
			secretID: secrets.count > 0 ? String(secrets[0]) : "",
			secretKey: secrets.count > 1 ? String(secrets[1]) : "",
			endpoint: comps.host.flatMap { URL(string: "\(comps.scheme ?? "")://\($0)") }
		)
		try self.init(name: config[Keys.name],
				  cloud: cloud,
				  path: comps.path,
				  baseURL: baseURL)
	}
	
	/// Create with dictionary.
	///
	/// - Format:
	///   - `{"source": string?, "bucket": string, "path": string?, "base_url": string?, "region": string?, "secret_id": string, "secret_key": string}`
	///   - `{"url": string, "base_url": string?}`
	public init(_ config: [String: JSON]) throws {
		if let url = config[Keys.url]?.stringValue {
			try self.init(urlString: url, baseURL: config[Keys.base_url]?.stringValue)
		} else {
			guard var path = config[Keys.bucket]?.stringValue else {
				throw WrapError(.invalid_parameter, "\(Keys.source) or \(Keys.bucket) empty")
			}
			if let _path = config[Keys.path]?.stringValue {
				path = PathComponents.url(path, _path).joined()
			}
			try self.init(name: config[Keys.source]?.stringValue,
					  cloud: .init(config),
					  path: path,
						  baseURL: config[Keys.base_url]?.stringValue)
		}
	}

	public var basepath: String? {
		path.isEmpty ? nil : path.joined()
	}

	public mutating func set(basepath: String) {
		removeBasepath()
		append(path: basepath)
	}

	public var urlString: String {
		var url = cloud.endpoint.map { $0.absoluteString } ?? ""
		url += PathComponents.urlSeparator
		url += bucket
		if !path.isEmpty {
			url += PathComponents.urlSeparator
			url += path.joined()
		}
		var query: [URLQueryItem] = []
		if let name = name {
			query.append(.init(name: Keys.name, value: name))
		}
		if let region = cloud.region {
			query.append(.init(name: Keys.region, value: region))
		}
		if !cloud.secretID.isEmpty {
			query.append(.init(name: Keys.secret, value: "\(cloud.secretID):\(cloud.secretKey)"))
		}
		if !query.isEmpty {
			url.append("?")
			url.append(query.map { "\($0.name)=\($0.value ?? "")" }.joined(separator: "&"))
		}
		return url
	}
	
	public func fullpath(_ path: String, separator: String = PathComponents.urlSeparator) -> String {
		self.path
			.appending(path)
			.with(separator: separator)
			.joined()
	}
	
	public func appending(path: String) -> Self {
		var dup = self
		dup.append(path: path)
		return dup
	}

	public func appending(paths: ArraySlice<String>) -> Self {
		var dup = self
		dup.append(paths: paths)
		return dup
	}

	public mutating func append(path: String) {
		let paths = Self.split(path: path)
		guard !paths.isEmpty else {
			return
		}
		append(paths: paths[...])
	}

	@inlinable
	public mutating func append(paths: String...) {
		append(paths: paths[...])
	}
	
	public mutating func append(paths: ArraySlice<String>) {
		let paths = paths.filter { !$0.isEmpty }
		guard !paths.isEmpty else {
			return
		}
		path.append(paths[...])
		if let baseURL, var url = URL(string: baseURL) {
			for path in paths {
				url = url.appendingPathComponent(path)
			}
			self.baseURL = url.absoluteString
		}
	}
	
	public mutating func removeBasepath() {
		path.removeAll()
		if let baseURL, var url = URLComponents(string: baseURL) {
			url.path = ""
			self.baseURL = url.url?.absoluteString
		}
	}
	
	public func removingBasepath() -> Self {
		var dup = self
		dup.removeBasepath()
		return dup
	}

	static func split(path: String) -> [String] {
		path.trimmingCharacters(in: .init(charactersIn: PathComponents.urlSeparator))
			.split(separator: PathComponents.urlSeparatorCharacter)
			.compactMap {
				let trimmed = $0.trimmingCharacters(in: .whitespacesAndNewlines)
				return trimmed.isEmpty ? nil : trimmed
			}
	}
}

/// Access control list
public enum ObjectStorageACL: String {
	/// Owner gets `FULL_CONTROL`. The AuthenticatedUsers group gets `READ` access.
	case authenticatedRead = "authenticated-read"

	/// Owner gets `FULL_CONTROL`. Amazon EC2 gets `READ` access to GET an Amazon Machine Image (AMI) bundle from Amazon S3.
	case awsExecRead = "aws-exec-read"

	/// Both the object owner and the bucket owner get `FULL_CONTROL` over the object.
	///
	/// If you specify this canned ACL when creating a bucket, Amazon S3 ignores it.
	case bucketOwnerFullControl = "bucket-owner-full-control"

	/// Object owner gets `FULL_CONTROL`. Bucket owner gets `READ` access.
	///
	/// If you specify this canned ACL when creating a bucket, Amazon S3 ignores it.
	case bucketOwnerRead = "bucket-owner-read"

	/// Owner gets `FULL_CONTROL`. No one else has access rights (default).
	case `private` = "private"

	/// Owner gets `FULL_CONTROL`. The AllUsers group gets `READ` access.
	case publicRead = "public-read"

	/// Owner gets `FULL_CONTROL`. The AllUsers group gets `READ` and `WRITE` access.
	///
	/// Granting this on a bucket is generally not recommended.
	case publicReadWrite = "public-read-write"
}

public struct ObjectStorageFile {
	public var key: String
	public var content: Data?
	public var eTag: String?
	public var lastModified: Time?
	public var contentLength: Int64?
	public var contentType: String?
	public var acl: ObjectStorageACL?

	public init(key: String,
				content: Data? = nil,
				eTag: String? = nil,
				lastModified: Time? = nil,
				contentLength: Int64? = nil,
				contentType: String? = nil,
				acl: ObjectStorageACL? = nil) {
		self.key = key
		self.content = content
		self.eTag = eTag
		self.lastModified = lastModified
		self.contentLength = contentLength
		self.contentType = contentType
		self.acl = acl
	}
}

public protocol ObjectStorageProvider: Sendable {
	var source: ObjectStorageSource { get set }
	func list(prefix: String, continueToken: String?, maxCount: Int) async throws -> ([ObjectStorageFile], String?)
	func head(key: String) async throws -> ObjectStorageFile?
	func get(key: String) async throws -> ObjectStorageFile?
	func put(key: String, content: Data, contentType: String,
			 expires: Date?, metadata: [String : String]?,
			 acl: ObjectStorageACL) async throws -> ObjectStorageFile
	func delete(key: String) async throws
	func delete(keys: [String]) async throws -> [WrapError]
	func signedURL(key: String, duration: TimeDuration) async throws -> URL
}

extension ObjectStorageProvider {
	public func signedURLExistOnly(key: String, duration: TimeDuration) async throws -> URL {
		_ = try await head(key: key)
		return try await signedURL(key: key, duration: duration)
	}
}

public struct ObjectStorageFileSystemProvider: ObjectStorageProvider {
	public static let name = "file_system"
	
	public var source: ObjectStorageSource
	let basepath: URL
	
	public init(source: ObjectStorageSource, basepath: URL) throws {
		self.basepath = basepath
		guard self.basepath.hasDirectoryPath else {
			throw WrapError(.invalid_parameter, "path(\(basepath) should be directory")
		}
		self.source = source
	}

	public func list(prefix: String, continueToken: String?, maxCount: Int) async throws -> ([ObjectStorageFile], String?) {
		let path = basepath.appendingPathComponent(prefix)
		let files = try FileManager.default.contentsOfDirectory(atPath: path.path)
		var items: [ObjectStorageFile] = []
		items.reserveCapacity(files.count)
		for file in files {
			guard let it = try await head(key: "\(prefix)\(PathComponents.systemPathSeparator)\(file)") else {
				continue
			}
			items.append(it)
		}
		return (items, nil)
	}
	
	public func head(key: String) async throws -> ObjectStorageFile? {
		let path = basepath.appendingPathComponent(key)
		if !FileManager.default.fileExists(atPath: path.path) {
			return nil
		}
		let attrs = try FileManager.default.attributesOfItem(atPath: path.path)
		return .init(
			key: key,
			lastModified: (attrs[.modificationDate] as? Date).map({ Time.init($0) }),
			contentLength: attrs[.size].flatMap(anyToInt64))
	}
	
	public func get(key: String) async throws -> ObjectStorageFile? {
		let path = basepath.appendingPathComponent(key)
		guard var file = try await head(key: key) else {
			return nil
		}
		file.content = FileManager.default.contents(atPath: path.path)
		return file
	}
	
	public func put(key: String, content: Data, contentType: String,
					expires: Date?, metadata: [String : String]?,
					acl: ObjectStorageACL) async throws -> ObjectStorageFile {
		let path = basepath.appendingPathComponent(key)
		try content.write(to: path)
		return .init(key: key, content: content, lastModified: .utc, contentLength: Int64(content.count), acl: acl)
	}

	public func delete(key: String) throws {
		let path = basepath.appendingPathComponent(key)
		if FileManager.default.fileExists(atPath: path.path) {
			try FileManager.default.removeItem(at: path)
		}
	}
	
	public func delete(keys: [String]) -> [WrapError] {
		keys.compactMap { key in
			do {
				try delete(key: key)
				return nil
			} catch {
				return Errors.internal.convertOrWrap(error)
			}
		}
	}
	
	public func signedURL(key: String, duration: TimeDuration) async throws -> URL {
		basepath.appendingPathComponent(key)
	}
}
