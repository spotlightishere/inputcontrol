//
//  CFMessageError.swift
//  inputcontrol
//
//  Created by Spotlight Deveaux on 2022-09-05.
//

import Foundation

/// Helper to map CFMessage statuses to Swift Errors, so that we can throw.
enum CFMessageError: String, Error {
    case sendTimeout = "Send timed out!"
    case receiveTimeout = "Receive timed out!"
    case isInvalid = "Port is invalid!"
    case transport = "Transport error!"
    case becameInvalid = "Port became invalid!"
    case nilReply = "Reply was nil!"
    case unknown = "Encountered unknown CFMessagePort error"

    init(from status: Int32) {
        switch status {
        case kCFMessagePortSendTimeout:
            self = .sendTimeout
        case kCFMessagePortReceiveTimeout:
            self = .receiveTimeout
        case kCFMessagePortIsInvalid:
            self = .receiveTimeout
        case kCFMessagePortTransportError:
            self = .transport
        case kCFMessagePortBecameInvalidError:
            self = .becameInvalid
        default:
            self = .unknown
        }
    }
}
