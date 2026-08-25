//
//  RosterLoader.swift
//  BrownsRoster1
//
//  Created by Gary Ilijevich on 8/24/26.
//

import Foundation
import SQLite3

enum RosterLoaderError: LocalizedError {
    case databaseNotFound
    case openFailed(String)
    case prepareFailed(String)
    case invalidProfileURL(String)

    var errorDescription: String? {
        switch self {
        case .databaseNotFound:
            return "Could not find browns.db in the app bundle."
        case .openFailed(let message):
            return "Could not open browns.db: \(message)"
        case .prepareFailed(let message):
            return "Could not prepare roster query: \(message)"
        case .invalidProfileURL(let value):
            return "Invalid player profile URL: \(value)"
        }
    }
}

struct RosterLoader {
    func loadPlayers() throws -> [Player] {
        guard let databaseURL = Bundle.main.url(forResource: "browns", withExtension: "db") else {
            throw RosterLoaderError.databaseNotFound
        }

        var database: OpaquePointer?
        let openResult = sqlite3_open_v2(databaseURL.path, &database, SQLITE_OPEN_READONLY, nil)
        guard openResult == SQLITE_OK else {
            let message = database.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown error"
            if let database {
                sqlite3_close(database)
            }
            throw RosterLoaderError.openFailed(message)
        }

        defer {
            sqlite3_close(database)
        }

        let query = """
            SELECT
                p.player_id,
                p.name,
                p.profile_url,
                p.image_url,
                p.image_number,
                r.number,
                r.position,
                r.height,
                r.weight,
                r.age,
                r.experience,
                r.college,
                r.roster_status,
                r.snapshot_date
            FROM players p
            JOIN roster_history r ON r.player_id = p.player_id
            WHERE r.snapshot_date = (
                SELECT MAX(snapshot_date)
                FROM roster_history
            )
            ORDER BY p.name COLLATE NOCASE
            """

        var statement: OpaquePointer?
        let prepareResult = sqlite3_prepare_v2(database, query, -1, &statement, nil)
        guard prepareResult == SQLITE_OK else {
            let message = database.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown error"
            throw RosterLoaderError.prepareFailed(message)
        }

        defer {
            sqlite3_finalize(statement)
        }

        var players: [Player] = []

        while sqlite3_step(statement) == SQLITE_ROW {
            let profileURLString = textValue(statement, column: 2)
            guard let profileURL = URL(string: profileURLString) else {
                throw RosterLoaderError.invalidProfileURL(profileURLString)
            }

            let remoteImageURLString = optionalTextValue(statement, column: 3)
            let player = Player(
                id: textValue(statement, column: 0),
                name: textValue(statement, column: 1),
                profileURL: profileURL,
                remoteImageURL: remoteImageURLString.flatMap(URL.init(string:)),
                imageNumber: Int(sqlite3_column_int(statement, 4)),
                number: textValue(statement, column: 5),
                position: textValue(statement, column: 6),
                height: textValue(statement, column: 7),
                weight: textValue(statement, column: 8),
                age: textValue(statement, column: 9),
                experience: textValue(statement, column: 10),
                college: textValue(statement, column: 11),
                rosterStatus: textValue(statement, column: 12),
                snapshotDate: textValue(statement, column: 13)
            )
            players.append(player)
        }

        return players
    }

    func headshotURL(for player: Player) -> URL? {
        Bundle.main.url(
            forResource: player.headshotResourceName,
            withExtension: "jpg",
            subdirectory: "headshots"
        ) ?? Bundle.main.url(
            forResource: player.headshotResourceName,
            withExtension: "jpg"
        )
    }

    private func textValue(_ statement: OpaquePointer?, column: Int32) -> String {
        guard let value = sqlite3_column_text(statement, column) else {
            return ""
        }

        return String(cString: value)
    }

    private func optionalTextValue(_ statement: OpaquePointer?, column: Int32) -> String? {
        guard sqlite3_column_type(statement, column) != SQLITE_NULL else {
            return nil
        }

        return textValue(statement, column: column)
    }
}
