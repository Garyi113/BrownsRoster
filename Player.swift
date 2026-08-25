//
//  Player.swift
//  BrownsRoster1
//
//  Created by Gary Ilijevich on 8/24/26.
//

import Foundation

struct Player: Identifiable, Hashable {
    let id: String
    let name: String
    let profileURL: URL
    let remoteImageURL: URL?
    let imageNumber: Int
    let number: String
    let position: String
    let height: String
    let weight: String
    let age: String
    let experience: String
    let college: String
    let rosterStatus: String
    let snapshotDate: String

    var headshotFileName: String {
        "\(imageNumber)_\(id).jpg"
    }

    var headshotResourceName: String {
        "\(imageNumber)_\(id)"
    }
}
