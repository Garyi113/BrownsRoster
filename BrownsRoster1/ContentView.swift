//
//  ContentView.swift
//  BrownsRoster1
//
//  Created by Gary Ilijevich on 8/24/26.
//

import SwiftUI

#if os(macOS)
import AppKit
typealias PlatformImage = NSImage
#else
import UIKit
typealias PlatformImage = UIImage
#endif

struct ContentView: View {
    @State private var players: [Player] = []
    @State private var loadingError: String?
    @State private var searchText = ""
    @State private var selectedPosition = FilterOption.all
    @State private var selectedStatus = FilterOption.all
    @State private var selectedSort = SortOption.lastName

    private let rosterLoader = RosterLoader()

    private var filteredPlayers: [Player] {
        let filtered = players.filter { player in
            let matchesSearch = searchText.isEmpty
                || player.name.localizedCaseInsensitiveContains(searchText)
                || player.position.localizedCaseInsensitiveContains(searchText)
                || player.number.localizedCaseInsensitiveContains(searchText)
                || player.college.localizedCaseInsensitiveContains(searchText)

            let matchesPosition = selectedPosition == FilterOption.all || player.positionFilterValue == selectedPosition
            let matchesStatus = selectedStatus == FilterOption.all || player.rosterStatus == selectedStatus

            return matchesSearch && matchesPosition && matchesStatus
        }

        return filtered.sorted(using: selectedSort)
    }

    private var positionOptions: [String] {
        [FilterOption.all] + Set(players.map(\.positionFilterValue)).sorted()
    }

    private var statusOptions: [String] {
        [FilterOption.all] + Set(players.map(\.rosterStatus)).sorted()
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                HeaderView(playerCount: players.count)

                if !players.isEmpty {
                    FilterBar(
                        selectedPosition: $selectedPosition,
                        selectedStatus: $selectedStatus,
                        selectedSort: $selectedSort,
                        positionOptions: positionOptions,
                        statusOptions: statusOptions
                    )
                }

                Group {
                    if let loadingError {
                        ContentUnavailableView(
                            "Roster Unavailable",
                            systemImage: "exclamationmark.triangle",
                            description: Text(loadingError)
                        )
                    } else if players.isEmpty {
                        ProgressView("Loading roster...")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if filteredPlayers.isEmpty {
                        ContentUnavailableView.search(text: searchText)
                    } else {
                        List(filteredPlayers) { player in
                            NavigationLink {
                                PlayerDetailView(player: player, rosterLoader: rosterLoader)
                            } label: {
                                PlayerRow(player: player, rosterLoader: rosterLoader)
                            }
                        }
                        .listStyle(.plain)
                    }
                }
            }
        }
        .searchable(text: $searchText, prompt: "Search players")
        .task {
            loadPlayers()
        }
    }

    private func loadPlayers() {
        do {
            players = try rosterLoader.loadPlayers()
            loadingError = nil
        } catch {
            loadingError = error.localizedDescription
        }
    }
}

private enum FilterOption {
    static let all = "All"
}

private enum SortOption: String, CaseIterable, Identifiable {
    case lastName = "Last Name"
    case number = "Number"

    var id: String { rawValue }

    func compare(_ first: Player, _ second: Player) -> Bool {
        switch self {
        case .lastName:
            let firstKey = lastNameSortKey(for: first)
            let secondKey = lastNameSortKey(for: second)
            if firstKey == secondKey {
                return first.name.localizedCaseInsensitiveCompare(second.name) == .orderedAscending
            }

            return firstKey.localizedCaseInsensitiveCompare(secondKey) == .orderedAscending
        case .number:
            let firstNumber = Int(first.number) ?? Int.max
            let secondNumber = Int(second.number) ?? Int.max
            if firstNumber == secondNumber {
                return first.name.localizedCaseInsensitiveCompare(second.name) == .orderedAscending
            }

            return firstNumber < secondNumber
        }
    }

    private func lastNameSortKey(for player: Player) -> String {
        let nameParts = player.name.split(separator: " ")
        guard let lastName = nameParts.last else {
            return player.name
        }

        return "\(lastName) \(player.name)"
    }
}

private extension Array where Element == Player {
    func sorted(using sortOption: SortOption) -> [Player] {
        sorted { first, second in
            sortOption.compare(first, second)
        }
    }
}

private extension Player {
    var positionFilterValue: String {
        position == "P" ? "K" : position
    }
}

private struct HeaderView: View {
    let playerCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Browns Roster")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal)
        .padding(.top)
        .padding(.bottom, 8)
    }

    private var subtitle: String {
        if playerCount == 0 {
            return "Codex practice project"
        }

        return "Codex practice project - \(playerCount) players"
    }
}

private struct FilterBar: View {
    @Binding var selectedPosition: String
    @Binding var selectedStatus: String
    @Binding var selectedSort: SortOption

    let positionOptions: [String]
    let statusOptions: [String]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                FilterMenu(title: "Position", selectedOption: $selectedPosition, options: positionOptions)
                FilterMenu(title: "Status", selectedOption: $selectedStatus, options: statusOptions)
                SortMenu(selectedSort: $selectedSort)
            }
            .padding(.horizontal)
        }
        .font(.subheadline)
        .padding(.bottom, 8)
    }
}

private struct FilterMenu: View {
    let title: String
    @Binding var selectedOption: String
    let options: [String]

    var body: some View {
        Menu {
            ForEach(options, id: \.self) { option in
                Button {
                    selectedOption = option
                } label: {
                    if selectedOption == option {
                        Label(option, systemImage: "checkmark")
                    } else {
                        Text(option)
                    }
                }
            }
        } label: {
            Label("\(title): \(selectedOption)", systemImage: "line.3.horizontal.decrease.circle")
        }
    }
}

private struct SortMenu: View {
    @Binding var selectedSort: SortOption

    var body: some View {
        Menu {
            ForEach(SortOption.allCases) { sortOption in
                Button {
                    selectedSort = sortOption
                } label: {
                    if selectedSort == sortOption {
                        Label(sortOption.rawValue, systemImage: "checkmark")
                    } else {
                        Text(sortOption.rawValue)
                    }
                }
            }
        } label: {
            Label("Sort: \(selectedSort.rawValue)", systemImage: "arrow.up.arrow.down")
        }
    }
}

private struct PlayerRow: View {
    let player: Player
    let rosterLoader: RosterLoader

    var body: some View {
        HStack(spacing: 12) {
            HeadshotImage(player: player, rosterLoader: rosterLoader, size: 64)

            Text(player.number)
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
                .frame(width: 64, height: 64)
                .minimumScaleFactor(0.6)
                .lineLimit(1)

            VStack(alignment: .leading, spacing: 5) {
                Text(player.name)
                    .font(.headline)
                    .lineLimit(1)

                Text("\(player.position) - \(player.height) - \(player.weight) lbs")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Text("\(player.college) - \(player.rosterStatus)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 6)
    }
}

private struct PlayerDetailView: View {
    let player: Player
    let rosterLoader: RosterLoader

    var body: some View {
        List {
            Section {
                VStack(spacing: 14) {
                    HeadshotImage(player: player, rosterLoader: rosterLoader, size: 180)

                    VStack(spacing: 4) {
                        Text(player.name)
                            .font(.title.bold())
                            .multilineTextAlignment(.center)

                        Text("\(player.number) - \(player.position)")
                            .font(.title2.weight(.bold))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding(.vertical, 12)
            }

            Section("Roster") {
                DetailRow(label: "Status", value: player.rosterStatus)
                DetailRow(label: "Height", value: player.height)
                DetailRow(label: "Weight", value: "\(player.weight) lbs")
                DetailRow(label: "Age", value: player.age)
                DetailRow(label: "Experience", value: player.experience)
                DetailRow(label: "College", value: player.college)
            }

            Section("Data") {
                DetailRow(label: "Player ID", value: player.id)
                DetailRow(label: "Snapshot", value: player.snapshotDate)
                DetailRow(label: "Headshot", value: player.headshotFileName)
            }
        }
        .navigationTitle(player.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct DetailRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .foregroundStyle(.secondary)

            Spacer(minLength: 16)

            Text(value)
                .multilineTextAlignment(.trailing)
        }
    }
}

private struct HeadshotImage: View {
    let player: Player
    let rosterLoader: RosterLoader
    let size: CGFloat

    var body: some View {
        if let image = loadImage() {
            image
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 8))
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.quaternary)

                VStack(spacing: 4) {
                    Image(systemName: "person.crop.square")
                        .font(.system(size: size * 0.35))

                    Text(initials)
                        .font(.caption.weight(.semibold))
                }
                .foregroundStyle(.secondary)
            }
            .frame(width: size, height: size)
        }
    }

    private var initials: String {
        player.name
            .split(separator: " ")
            .prefix(2)
            .compactMap(\.first)
            .map(String.init)
            .joined()
    }

    private func loadImage() -> Image? {
        guard
            let url = rosterLoader.headshotURL(for: player),
            let data = try? Data(contentsOf: url),
            let platformImage = PlatformImage(data: data)
        else {
            return nil
        }

        #if os(macOS)
        return Image(nsImage: platformImage)
        #else
        return Image(uiImage: platformImage)
        #endif
    }
}

#Preview {
    ContentView()
}
