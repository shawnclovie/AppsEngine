//
//  ObjectStorageTests.swift
//  
//
//  Created by Shawn Clovie on 2023/4/15.
//

import XCTest
@testable import AppsEngine

final class ObjectStorageTests: XCTestCase {
	func testObjectStorage() throws {
		let basepath = "rest_path"
		let urlAWS = "/my_bucket/\(basepath)?name=aws&region=us-east-1&secret=SECRET_ID:SECRET_KEY"
		let urlOSS = "http://oss-cn-beijing.aliyuncs.com/my_bucket/\(basepath)?secret=SECRET_ID:SECRET_KEY"
		for url in [urlAWS, urlOSS] {
			let source = try ObjectStorageSource(urlString: url, baseURL: nil)
			let source2 = try ObjectStorageSource(urlString: source.urlString, baseURL: nil)
			XCTAssertEqual(source, source2)
			XCTAssertEqual("\(basepath)/foo", source.fullpath("foo"))
		}
	}

	func testObjectStorageAppending() throws {
		let baseURL = "https://foo.bar"
		let source = try ObjectStorageSource(name: "aws", cloud: .init(region: "us-east-1", secretID: "A", secretKey: "B", endpoint: nil), path: "foo", baseURL: baseURL)
		XCTAssertEqual(["foo", nil], [source.bucket, source.basepath])
		XCTAssertEqual(nil, source.appending(path: "").basepath)
		XCTAssertEqual(nil, source.appending(path: "//").basepath)
		XCTAssertEqual("bar", source.appending(path: "bar").basepath)
		XCTAssertEqual(baseURL, source.baseURL)
		XCTAssertThrowsError(try ObjectStorageSource(name: "oss", cloud: source.cloud, path: "", baseURL: nil))
		do {
			let appended = source.appending(path: "bar")
			XCTAssertEqual(["foo", "bar", "\(baseURL)/bar"],
						   [appended.bucket,
							appended.basepath,
							appended.baseURL])
			var removedBasepath = appended.removingBasepath()
			XCTAssertEqual(["foo", nil, baseURL],
						   [removedBasepath.bucket,
							removedBasepath.basepath,
							removedBasepath.baseURL])
			removedBasepath.bucket = "bar"
			XCTAssertEqual(["bar", nil], [removedBasepath.bucket, removedBasepath.basepath])
			var replaceBasepath = source.appending(path: "foo/bar")
			replaceBasepath.set(basepath: "b/a/r")
			XCTAssertEqual(["foo", "b/a/r"], [replaceBasepath.bucket, replaceBasepath.basepath])
			replaceBasepath.set(basepath: "")
			XCTAssertEqual(["foo", nil], [replaceBasepath.bucket, replaceBasepath.basepath])
		}
	}
}
