//
//  SandboxExtensions.swift
//  inputcontrol
//
//  Created by Spotlight Deveaux on 2022-09-06.
//

import Foundation

enum ConsumptionError: Error {
    case nonZero
    case noToken
}

// We'll need to manually invoke our functions,
// as linking against libsystem_sandbox.dylib itself would make
// App Review not too happy.
let sandboxHandle = dlopen("/usr/lib/system/libsystem_sandbox.dylib", RTLD_NOW)
let consumeMachHandle = dlsym(sandboxHandle, "sandbox_consume_mach_extension")
let issueFsHandle = dlsym(sandboxHandle, "sandbox_issue_fs_extension")
let consumeFsHandle = dlsym(sandboxHandle, "sandbox_consume_fs_extension")

/// Consumes a Mach extension.
/// - Parameter token: Issued Mach extension string
/// - Throws: Should consumption fail
func consumeMachExtension(token: String) throws {
    // We've been granted an extension! Time to consume.
    let sandboxToken = token.cString(using: .utf8)!

    // Original definition:
    // int sandbox_consume_mach_extension(const char *ext_token, const char **name)
    typealias consumeFunc = @convention(c) (_ ext_token: UnsafePointer<CChar>, _ name: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?) -> Int
    let sandbox_consume_mach_extension = unsafeBitCast(consumeMachHandle, to: consumeFunc.self)

    // I have no clue what the "name" paramater is, and it seems to always be null.
    // We'll omit it - not our main focus :)
    let result = sandbox_consume_mach_extension(sandboxToken, nil)
    if result != 0 {
        print("Encountered status \(result) when consuming Mach extension!")
        throw ConsumptionError.nonZero
    }
}

func issueFilesystemExtension(path: URL) throws -> String {
    let filePath = path.path().cString(using: .utf8)!

    // Original definition:
    // int sandbox_issue_fs_extension(const char *path, uint64_t flags, const char **ext_token)
    typealias consumeFunc = @convention(c) (_ path: UnsafePointer<CChar>, _ flags: UInt64, _ extToken: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?) -> Int
    let sandbox_issue_fs_extension = unsafeBitCast(issueFsHandle, to: consumeFunc.self)

    var extToken: UnsafeMutablePointer<CChar>?
    // We only want to issue for the path, and allow the coordinator to read.
    // 0x1 allows path-based issuance, and 0x4 allows reading.
    let flags: UInt64 = 5

    let result = sandbox_issue_fs_extension(filePath, flags, &extToken)
    if result != 0 {
        print("Encountered status \(result) when issuing filesystem extension!")
        throw ConsumptionError.nonZero
    }

    guard let extToken else {
        throw ConsumptionError.noToken
    }

    return String(cString: extToken, encoding: .utf8)!
}

func consumeFileExtension(token: String) throws {
    let sandboxToken = token.cString(using: .utf8)!

    // Original definition:
    // int sandbox_consume_fs_extension(const char *ext_token, char **path);
    typealias consumeFunc = @convention(c) (_ ext_token: UnsafePointer<CChar>, _ path: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?) -> Int
    let sandbox_consume_fs_extension = unsafeBitCast(consumeFsHandle, to: consumeFunc.self)

    let result = sandbox_consume_fs_extension(sandboxToken, nil)
    if result != 0 {
        print("Encountered status \(result) when consuming filesystem extension!")
        throw ConsumptionError.nonZero
    }
}
