//
//  RosterLoader.swift
//  BrownsRoster1
//
//  Created by Gary Ilijevich on 8/24/26.
//

import Foundation
import CryptoKit
import SQLite3

enum RosterLoaderError: LocalizedError {
    case databaseNotFound
    case openFailed(String)
    case prepareFailed(String)
    case invalidProfileURL(String)

    var errorDescription: String? {
        switch self {
        case .databaseNotFound:
            return "Could not find browns.db."
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
        guard let databaseURL = databaseURL() else {
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
            subdirectory: "Resources/headshots"
        ) ?? Bundle.main.url(
            forResource: player.headshotResourceName,
            withExtension: "jpg",
            subdirectory: "headshots"
        ) ?? Bundle.main.url(
            forResource: player.headshotResourceName,
            withExtension: "jpg"
        )
    }

    private func databaseURL() -> URL? {
        RosterUpdater.downloadedDatabaseURLIfAvailable() ?? Bundle.main.url(
            forResource: "browns",
            withExtension: "db",
            subdirectory: "Resources"
        ) ?? Bundle.main.url(forResource: "browns", withExtension: "db")
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

struct RosterManifest: Codable, Equatable {
    let version: String
    let updatedAt: String?
    let playerCount: Int
    let sha256: String
    let databaseUrl: URL
}

struct RosterDebugInfo: Equatable {
    let source: String
    let manifestVersion: String?
    let manifestUpdatedAt: String?
    let manifestPlayerCount: Int?

    var sourceSummary: String {
        if let manifestPlayerCount {
            return "Source: \(source) | Published: \(manifestPlayerCount)"
        }

        return "Source: \(source)"
    }

    var versionSummary: String {
        guard let manifestVersion else {
            return "Database version: Bundled"
        }

        return "Database version: \(manifestVersion)"
    }

    var updatedSummary: String {
        guard let manifestUpdatedAt else {
            return "Updated: Bundled with app"
        }

        return "Updated: \(manifestUpdatedAt.formattedRosterTimestamp)"
    }
}

struct RosterUpdater {
    private let manifestURL = URL(
        string: "https://garyi113.github.io/BrownsRoster/roster/roster_manifest.json"
    )!

    func updateIfNeeded() async throws -> Bool {
        let (manifestData, _) = try await URLSession.shared.data(for: Self.uncachedRequest(for: manifestURL))
        let remoteManifest = try JSONDecoder().decode(RosterManifest.self, from: manifestData)

        if let localManifest = try? Self.localManifest(), localManifest.sha256 == remoteManifest.sha256 {
            return false
        }

        let databaseURL = Self.cacheBustedDatabaseURL(for: remoteManifest)
        let (databaseData, _) = try await URLSession.shared.data(for: Self.uncachedRequest(for: databaseURL))
        guard Self.sha256Hex(for: databaseData) == remoteManifest.sha256 else {
            throw RosterUpdaterError.hashMismatch
        }

        try Self.install(databaseData: databaseData, manifestData: manifestData)
        return true
    }

    private static func uncachedRequest(for url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        return request
    }

    private static func cacheBustedDatabaseURL(for manifest: RosterManifest) -> URL {
        guard var components = URLComponents(url: manifest.databaseUrl, resolvingAgainstBaseURL: false) else {
            return manifest.databaseUrl
        }

        components.queryItems = [
            URLQueryItem(name: "sha256", value: manifest.sha256)
        ]
        return components.url ?? manifest.databaseUrl
    }

    static func downloadedDatabaseURLIfAvailable() -> URL? {
        let url = downloadedDatabaseURL
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    static func currentDebugInfo() -> RosterDebugInfo {
        guard downloadedDatabaseURLIfAvailable() != nil else {
            return RosterDebugInfo(
                source: "Bundled",
                manifestVersion: nil,
                manifestUpdatedAt: nil,
                manifestPlayerCount: nil
            )
        }

        let manifest = try? localManifest()
        return RosterDebugInfo(
            source: "Downloaded",
            manifestVersion: manifest?.version,
            manifestUpdatedAt: manifest?.updatedAt,
            manifestPlayerCount: manifest?.playerCount
        )
    }

    private static func applicationSupportDirectory() throws -> URL {
        let directory = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        .appendingPathComponent("BrownsRoster1", isDirectory: true)

        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )

        return directory
    }

    private static var downloadedDatabaseURL: URL {
        get {
            do {
                return try applicationSupportDirectory().appendingPathComponent("browns.db")
            } catch {
                return FileManager.default.temporaryDirectory.appendingPathComponent("browns.db")
            }
        }
    }

    private static var localManifestURL: URL {
        get {
            do {
                return try applicationSupportDirectory().appendingPathComponent("roster_manifest.json")
            } catch {
                return FileManager.default.temporaryDirectory.appendingPathComponent("roster_manifest.json")
            }
        }
    }

    private static func localManifest() throws -> RosterManifest {
        let data = try Data(contentsOf: localManifestURL)
        return try JSONDecoder().decode(RosterManifest.self, from: data)
    }

    private static func sha256Hex(for data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func install(databaseData: Data, manifestData: Data) throws {
        let directory = try applicationSupportDirectory()
        let temporaryDatabaseURL = directory.appendingPathComponent("browns.db.download")
        let temporaryManifestURL = directory.appendingPathComponent("roster_manifest.json.download")

        try databaseData.write(to: temporaryDatabaseURL, options: .atomic)
        try manifestData.write(to: temporaryManifestURL, options: .atomic)

        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: downloadedDatabaseURL.path) {
            try fileManager.removeItem(at: downloadedDatabaseURL)
        }
        if fileManager.fileExists(atPath: localManifestURL.path) {
            try fileManager.removeItem(at: localManifestURL)
        }

        try fileManager.moveItem(at: temporaryDatabaseURL, to: downloadedDatabaseURL)
        try fileManager.moveItem(at: temporaryManifestURL, to: localManifestURL)
    }
}

private extension String {
    var formattedRosterTimestamp: String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [
            .withInternetDateTime,
            .withFractionalSeconds
        ]

        let date = formatter.date(from: self) ?? {
            let fallbackFormatter = ISO8601DateFormatter()
            fallbackFormatter.formatOptions = [.withInternetDateTime]
            return fallbackFormatter.date(from: self)
        }()

        guard let date else {
            return self
        }

        return date.formatted(
            date: .abbreviated,
            time: .shortened
        )
    }
}

enum RosterUpdaterError: LocalizedError {
    case hashMismatch

    var errorDescription: String? {
        switch self {
        case .hashMismatch:
            return "Downloaded roster database did not match the published manifest."
        }
    }
}
