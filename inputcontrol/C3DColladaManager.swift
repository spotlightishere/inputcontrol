//
//  C3DColladaManager.swift
//  inputcontrol
//
//  Created by Spotlight Deveaux on 2022-09-05.
//

import Foundation

func obtainFileExtension(for sourcePath: String) throws {
    log(entry: "Requesting file extension for \(sourcePath)...")
    // Create a fake COLLADA file, and issue an extension for it.
    let colladaPath = try synthesizeColladaFile(for: sourcePath)
    let colladaFileExtension = try issueFilesystemExtension(path: colladaPath)

    // Request an extension for our source path via C3DColladaResourcesCoordinator.
    let sourcePathExtension = try sendColladaRequest(path: colladaPath, pathExtension: colladaFileExtension)
    try consumeFileExtension(token: sourcePathExtension)
    log(entry: "...obtained.")
}

// MARK: DAE Synthesizing

func synthesizeColladaFile(for path: String) throws -> URL {
    // Remove our faux DAE if already created.
    let daePath = try temporaryFile(named: "faux.dae")

    // Now, synthesize a DAE for our path.
    let fileContents = """
    <?xml version="1.0"?>
    <COLLADA xmlns="http://www.collada.org/2005/11/COLLADASchema" version="1.4.1">
        <library_images>
            <image id="technique" name="technique">
                <init_from>\(path)</init_from>
            </image>
        </library_images>
        <scene>
            <instance_visual_scene url="#Scene"/>
        </scene>
    </COLLADA>
    """.data(using: .utf8)

    try fileContents?.write(to: daePath)

    return daePath
}

// MARK: C3DColladaResourcesCoordinator Communication

enum ColladaError: Error {
    case nonZeroStatus
    case unknownExtensions
}

func sendColladaRequest(path: URL, pathExtension: String) throws -> String {
    let connection = xpc_connection_create("com.apple.SceneKit.C3DColladaResourcesCoordinator", .main)
    xpc_connection_set_event_handler(connection) { inbound in
        if xpc_get_type(inbound) == XPC_TYPE_ERROR, xpc_equal(inbound, XPC_ERROR_CONNECTION_INVALID) {
            // No use spamming log :)
            return
        }
    }

    //
    // Request
    //
    // We need to provide a dictionary similar to the following:
    //
    //    {
    //        "kC3DColladaResourcesServiceRequestArgumentsKey": dictionary {
    //            "kC3DColladaResourcesCoordinatorRequestAssetDirectoryURLsKey": array [
    //                n => dictionary,    // See CFURLObject for information regarding this format.
    //                                    // These are all CFURLs to assets.
    //            ],
    //            "kC3DColladaResourcesCoordinatorRequestExtensionKey": string,  // Sandbox extension for our DAE.
    //            "kC3DColladaResourcesCoordinatorRequestURLKey": dictionary,    // CFURL dictionary for our DAE.
    //         }
    //    }
    //
    // We specify an assets directory of /, allowing us to dictate what asset URLs
    // should have sandbox extensions be granted to us.

    // Synthesize a request.
    let requestArguments = xpc_dictionary_create_empty()
    xpc_dictionary_set_value(requestArguments, "kC3DColladaResourcesCoordinatorRequestURLKey", CFURLObject(path))
    xpc_dictionary_set_string(requestArguments, "kC3DColladaResourcesCoordinatorRequestExtensionKey", pathExtension)
    // Note that we specify an assets directory of "/".
    let directoryURLs = xpc_array_create([CFURLObject(URL(filePath: "/"))], 1)
    xpc_dictionary_set_value(requestArguments, "kC3DColladaResourcesCoordinatorRequestAssetDirectoryURLsKey", directoryURLs)

    let request = xpc_dictionary_create_empty()
    xpc_dictionary_set_value(request, "kC3DColladaResourcesServiceRequestArgumentsKey", requestArguments)

    xpc_connection_activate(connection)

    //
    // Response
    //
    // We're sent a dictionary in a format similar to
    //
    //   {
    //       "kC3DColladaResourcesServiceReplyReturnCodeKey": uint64,
    //       "kC3DColladaResourcesServiceReplyArgumentsKey": dictionary {
    //           "kC3DColladaResourcesCoordinatorReplyExtensionsKey": array [
    //               n => dictionary with {
    //                   "url": dictionary,   // See CFURLObject for information regarding this format.
    //                   "type": "image",     // We can also have type "shader", but that seems to be unimplemented.
    //                   "extension": string, // The extension we need to claim.
    //               }
    //           ]
    //       }
    //   }
    //
    // We only put in one file, so here's hoping the array only has one key.

    let response = xpc_connection_send_message_with_reply_sync(connection, request)
    xpc_connection_cancel(connection)

    guard xpc_dictionary_get_uint64(response, "") == 0 else {
        throw ColladaError.nonZeroStatus
    }

    let responseArguments = xpc_dictionary_get_value(response, "kC3DColladaResourcesServiceReplyArgumentsKey")!
    let extensionArray = xpc_dictionary_get_array(responseArguments, "kC3DColladaResourcesCoordinatorReplyExtensionsKey")!

    // We should have exactly one extension granted.
    guard xpc_array_get_count(extensionArray) == 1 else {
        throw ColladaError.unknownExtensions
    }

    // Get our extension!
    let firstExtension = xpc_array_get_dictionary(extensionArray, 0)!
    let sandboxExtension = xpc_dictionary_get_string(firstExtension, "extension")!

    return String(cString: sandboxExtension)
}

// !!! HACK !!!
// I couldn't get CFXPCCreateXPCObjectFromCFObject to work nicely,
// so this is how CoreFoundation.framework converts a CFURL to an XPC object.
// The URL must utilize the file:// schema.
//
// I imagine this varies from version to version
// and should not be relied on, but here we are anyway.
func CFURLObject(_ path: URL) -> xpc_object_t {
    let url = path.absoluteString
    let object = xpc_dictionary_create_empty()

    // C3853DCC-9776-4114-B6C1-FD9F51944A6D
    xpc_dictionary_set_uuid(object, "com.apple.CFURL.magic", [0xC3, 0x85, 0x3D, 0xCC, 0x97, 0x76, 0x41, 0x14, 0xB6, 0xC1, 0xFD, 0x9F, 0x51, 0x94, 0x4A, 0x6D])
    xpc_dictionary_set_string(object, "com.apple.CFURL.string", url)
    xpc_dictionary_set_value(object, "com.apple.CFURL.base", xpc_null_create())
    return object
}
