# Browns Roster

Browns Roster is a SwiftUI practice project that displays a Cleveland Browns roster from a local SQLite database. The app loads player data, matches players to local headshot images, and presents the roster in a searchable, filterable list.

## Features

- SwiftUI roster list
- Local SQLite roster loading
- Local bundled headshot support
- Search by player name, jersey number, position, or college
- Filter by position and roster status
- Sort by last name or jersey number
- Player detail screen with full roster information
- Fallback image state when a headshot is unavailable

## Project Structure

```text
BrownsRoster1/
  BrownsRoster1/
    Assets.xcassets
    BrownsRoster1App.swift
    ContentView.swift
    Player.swift
    RosterLoader.swift
    browns.db
    headshots/
  BrownsRoster1Tests/
  BrownsRoster1UITests/
```

## Local Data Files

The app expects these local files to exist when running with real roster data:

```text
BrownsRoster1/BrownsRoster1/browns.db
BrownsRoster1/BrownsRoster1/headshots/
```

These files are intentionally ignored by Git and are not included in this repository:

```gitignore
BrownsRoster1/browns.db
BrownsRoster1/headshots/
```

This keeps the repository focused on the app source code and avoids committing the database and image assets.

## Running the App

1. Open `BrownsRoster1.xcodeproj` in Xcode.
2. Make sure `browns.db` is present at `BrownsRoster1/BrownsRoster1/browns.db`.
3. Make sure the `headshots` folder is present at `BrownsRoster1/BrownsRoster1/headshots/`.
4. Select the `BrownsRoster1` scheme.
5. Build and run.

If the data files are missing, the app will build, but roster loading or headshot display will not show the complete local data experience.

## Implementation Notes

- `Player.swift` defines the roster model.
- `RosterLoader.swift` opens `browns.db` read-only from the app bundle and maps the latest roster snapshot into `Player` values.
- `ContentView.swift` contains the roster UI, filtering, sorting, searching, row display, and detail screen.
- Headshots are matched by `imageNumber` and `player.id`, using filenames like `1001_tre-avery.jpg`.

## Requirements

- Xcode
- SwiftUI-compatible Apple platform target
- Local roster database and headshot files for full data display
