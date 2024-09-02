//
//  FileManager+.swift
//  
//
//  Created by Shawn Clovie on 2023/4/10.
//

import Foundation

extension FileManager {
	/// Find `file` in `directory`.
	/// - Parameters:
	///   - file: Filename
	///   - directory: Full path of directory
	/// - Returns: each file URL found.
	public func find(file: String, inDirectory directory: String = FileManager.default.currentDirectoryPath) -> [URL] {
		let dir = URL(fileURLWithPath: directory)
		guard let enu = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else {
			return []
		}
		var paths: [URL] = []
		for case let fileURL as URL in enu
		where fileURL.lastPathComponent == file {
			paths.append(fileURL)
		}
		return paths
	}

	/// Make sure `directory` is a directory.
	public func makeExist(directory: URL) throws {
		if fileExists(atPath: directory.path) {
			if try directory.resourceValues(forKeys: [.isDirectoryKey]).isDirectory != true {
				try removeItem(at: directory)
				try createDirectory(at: directory, withIntermediateDirectories: true)
			}
		} else {
			try createDirectory(at: directory, withIntermediateDirectories: true)
		}
	}
}
