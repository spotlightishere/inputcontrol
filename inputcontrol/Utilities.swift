//
//  Utilities.swift
//  inputcontrol
//
//  Created by Spotlight Deveaux on 2022-11-19.
//

import Foundation

/// Returns a path for a temporarily file, deleting it if necessary.
/// - Parameter filename: The filename to utilize.
/// - Throws: Should removal fail.
/// - Returns: A URL that the temporary file can be created at.
func temporaryFile(named filename: String) throws -> URL {
    let temporaryPath = URL.temporaryDirectory.appending(path: filename)
    let temporaryPathString = temporaryPath.path()
    if FileManager.default.fileExists(atPath: temporaryPathString) {
        try FileManager.default.removeItem(at: temporaryPath)
    }

    return temporaryPath
}
