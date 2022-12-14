//
//  IMKAgentManager.swift
//  inputcontrol
//
//  Created by Spotlight Deveaux on 2022-09-05.
//

import Foundation

// MARK: Real Extension Bundles

struct ExtensionBundle: Equatable {
    // The filename of this bundle on disk, present under
    // /System/Library/Input Methods/<wrapper>.app/Contents/PlugIns.
    let bundleFilename: String
    // The CFBundleIdentifier of our extension.
    let bundleIdentifier: String
}

// Extension types by a fair dice roll.
enum ExtensionTypes {
    static var koren: ExtensionBundle {
        ExtensionBundle(bundleFilename: "KIM_Extension.appex", bundleIdentifier: "com.apple.inputmethod.Korean")
    }

    static var tcim: ExtensionBundle {
        ExtensionBundle(bundleFilename: "TCIM_Extension.appex", bundleIdentifier: "com.apple.inputmethod.TCIM")
    }
}

// MARK: Faux Extension Bundle

func createFauxExtension(via extensionBundle: ExtensionBundle, for machService: String) throws -> String {
    // Remove our faux extension if already created.
    let extensionPath = try temporaryFile(named: extensionBundle.bundleFilename)

    // When imklaunchagent is called to launch, it optionally accepts
    // kInputMethodNeedSandboxExtensionKey as an option, sending us a seatbelt extension.
    let contentsPath = extensionPath.appending(path: "Contents")
    try FileManager.default.createDirectory(atPath: contentsPath.path(), withIntermediateDirectories: true)

    // Here, we utilize a bundle identifier that
    // imklaunchagent hopefully already knows.
    // Note that it grants the extension for the controlled InputMethodConnectionName
    // value within the bundle's Info.plist.
    let infoPath = contentsPath.appending(path: "Info.plist").path()
    let infoContents = [
        "CFBundleIdentifier": extensionBundle.bundleIdentifier,
        "InputMethodConnectionName": machService,
    ] as [String: String]
    let infoData = try PropertyListEncoder().encode(infoContents)
    FileManager.default.createFile(atPath: infoPath, contents: infoData)

    return extensionPath.path()
}

// MARK: imklaunchagent Communication

/// The structure for our request to the launcher.
struct LauncherRequest: Codable {
    let kInputMethodExecutablePathKey: String
    let kInputMethodBundleIdentifierKey: String
    let kInputMethodNeedSandboxExtensionKey: Bool
    let kInputMethodIsNSExtensionKey: Bool
}

/// The structure we hope to receive in return.
struct LauncherResponse: Codable {
    let kInputMethodLaunchStatusKey: Int
    let kInputMethodSandboxTokenKey: String
}

func requestSandboxToken(via fauxBundlePath: String, identifier fauxBundleIdentifer: String) throws -> String {
    // Now that we've created our synthesized bundle, we reach out to imklaunchagent.
    let connection = CFMessagePortCreateRemote(kCFAllocatorDefault, "com.apple.inputmethodkit.launcher" as CFString)

    // imklaunchagent expects an XML property list via its mesasge port.
    let plistEncoder = PropertyListEncoder()
    plistEncoder.outputFormat = .xml

    // Once more, we specify a legitimate bundle identifier so that imklaunchagent
    // somewhat recognizes this bundle - more directly, an endpoint cached.
    // For example, this may be com.apple.inputmethod.Korean.
    //
    // It's important we also specify that this is a NSExtension, otherwise the system
    // won't grant us a sandbox extension. (There appears to be a predefined list
    // of non-extension input methods.)
    let request = LauncherRequest(
        kInputMethodExecutablePathKey: fauxBundlePath,
        kInputMethodBundleIdentifierKey: fauxBundleIdentifer,
        kInputMethodNeedSandboxExtensionKey: true,
        kInputMethodIsNSExtensionKey: true
    )
    let requestPlist = try plistEncoder.encode(request)
    let requestData = requestPlist as CFData

    // The following timeouts are chosen purely out of thin air, to put it politely.
    var replyUnmanaged: Unmanaged<CFData>?
    let replyStatusInt = CFMessagePortSendRequest(connection, 8000, requestData, 5, 60, CFRunLoopMode.defaultMode.rawValue, &replyUnmanaged)

    // Ensure our request was successful.
    let replyStatus = CFMessageError(from: replyStatusInt)
    guard replyStatus == .unknown else {
        CFMessagePortInvalidate(connection)
        throw replyStatus
    }
    guard let replyUnmanaged else {
        CFMessagePortInvalidate(connection)
        throw CFMessageError.nilReply
    }

    let replyData = replyUnmanaged.takeRetainedValue() as Data
    let reply = try PropertyListDecoder().decode(LauncherResponse.self, from: replyData)

    // Lastly, clean up.
    CFMessagePortInvalidate(connection)
    return reply.kInputMethodSandboxTokenKey
}

func obtainMachExtension(for machListener: String, via extensionBundle: ExtensionBundle) throws {
    log(entry: "Obtaining Mach extension for \(machListener)...")

    // First, create our fake extension.
    let fauxExtensionPath = try createFauxExtension(via: extensionBundle, for: machListener)
    // Next, request a Mach extension/sandbox token to redeem.
    let sandboxToken = try requestSandboxToken(via: fauxExtensionPath, identifier: extensionBundle.bundleIdentifier)
    // Lastly, redeem our token.
    try consumeMachExtension(token: sandboxToken)

    log(entry: "...obtained.")
}
