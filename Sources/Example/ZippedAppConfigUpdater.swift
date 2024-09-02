//
//  ZippedAppConfigUpdater.swift
//  
//
//  Created by Shawn Clovie on 2023/3/10.
//

import AppsEngine
import Foundation
import SWCompression

public final class ZippedAppConfigUpdater: AppConfigUpdator {
	public static let appConfigExt = ".zip"
	public static let updateTMPDir = "update_tmp"

	public let provider: ObjectStorageProvider

	public init(provider: ObjectStorageProvider) {
		self.provider = provider
	}

	public func update(_ config: EngineConfig, input: AppConfigUpdateInput) async throws -> AppConfigUpdateResult {
		let curDir = FileManager.default.currentDirectoryPath
		let updateTMPDir = URL(fileURLWithPath: curDir)
			.appendingPathComponent(Self.updateTMPDir)
		try Self.prepare(directory: input.rootPath)
		try Self.prepare(directory: updateTMPDir)

		input.logger.log(.debug, "start download apps", .init("cur_dir", curDir))
		let providerPath = input.appSource.path ?? ""
		let keyPrefix = providerPath +
			(providerPath.isEmpty || providerPath.hasSuffix(PathComponents.urlSeparator) ? "" : PathComponents.urlSeparator)
		let appFilesStatus = try await downloadAppList(provider: provider, keyPrefix: keyPrefix)
		var result = AppConfigUpdateResult()
		try removeDeletedAppsDirectories(incomingAppIDs: .init(appFilesStatus.keys), on: input.rootPath)
		for (appID, lastModified) in appFilesStatus {
			guard input.includes(appID: appID) else { continue }
			guard input.shouldUpdate(appID: appID, updateTime: lastModified)
			else {
				result.skipSinceNotChanged(appID: appID)
				continue
			}
			let tmpAppDir = updateTMPDir.appendingPathComponent(appID)
			let file: ObjectStorageFile
			do {
				let key = "\(keyPrefix)\(appID)\(Self.appConfigExt)"
				file = try await downloadZippedAppData(provider: provider, key: key, appDir: tmpAppDir)
			} catch {
				result.skip(appID: appID, since: Errors.oss_unavailable.convertOrWrap(error, extra: ["reason": .string("download app zip failed")]))
				continue
			}
			// test app valid
			let testResult = await input.testAppConfig(config, directory: tmpAppDir)
			result.testDidFinish(appID: appID, modifyTime: file.lastModified ?? .utc, testResult)
			let appDir = input.rootPath.appendingPathComponent(appID)
			if FileManager.default.fileExists(atPath: appDir.path) {
				try FileManager.default.removeItem(at: appDir)
			}
			try FileManager.default.moveItem(at: tmpAppDir, to: appDir)
		}
		return result
	}
	
	func downloadAppList(provider: ObjectStorageProvider, keyPrefix: String) async throws -> [String: Time] {
		var nextToken: String?
		var status: [String: Time] = [:]
		repeat {
			let (files, next) = try await provider.list(prefix: keyPrefix, continueToken: nextToken, maxCount: 128)
			for file in files {
				guard let appID = appID(file: file),
					  let modTime = file.lastModified else { continue }
				status[appID] = modTime
			}
			nextToken = next
		} while nextToken != nil
		return status
	}
	
	func appID(file: ObjectStorageFile) -> String? {
		let filename = URL(fileURLWithPath: file.key).lastPathComponent
		guard let range = filename.range(of: Self.appConfigExt, options: [.backwards]) else {
			return nil
		}
		return String(filename[..<range.lowerBound])
	}
	
	func removeDeletedAppsDirectories(incomingAppIDs: Set<String>, on rootPath: URL) throws {
		for file in try FileManager.default.contentsOfDirectory(at: rootPath, includingPropertiesForKeys: nil) {
			if !incomingAppIDs.contains(file.lastPathComponent) {
				try FileManager.default.removeItem(at: file)
			}
		}
	}
	
	func downloadZippedAppData(provider: ObjectStorageProvider, key: String, appDir: URL) async throws -> ObjectStorageFile {
		guard let file = try await provider.get(key: key),
			  let content = file.content else {
			throw WrapError(.not_found, "no_data", ["key": .string(key)])
		}
		if FileManager.default.fileExists(atPath: appDir.path) {
			try FileManager.default.removeItem(at: appDir)
		}
		try FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
		let zipFile = appDir.appendingPathComponent("_.zip")
		try content.write(to: zipFile)
		defer {
			try? FileManager.default.removeItem(at: zipFile)
		}
		let entries = try ZipContainer.open(container: content)
		for entry in entries where entry.info.type == .regular {
			guard let data = entry.data else {
				continue
			}
			let path = appDir.appendingPathComponent(entry.info.name)
			let dir = path.deletingLastPathComponent()
			if !FileManager.default.fileExists(atPath: dir.path) {
				try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
			}
			try data.write(to: path)
		}
		return file
	}
	
	static func prepare(directory: URL) throws {
		let fileMGR = FileManager.default
		if fileMGR.fileExists(atPath: directory.path) {
			if try directory.resourceValues(forKeys: [.isDirectoryKey]).isDirectory != true {
				try fileMGR.removeItem(at: directory)
				try fileMGR.createDirectory(at: directory, withIntermediateDirectories: true)
			}
		} else {
			try fileMGR.createDirectory(at: directory, withIntermediateDirectories: true)
		}
	}
}
