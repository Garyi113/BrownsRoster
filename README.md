# Browns Roster

Browns Roster is a SwiftUI practice project that displays a Cleveland Browns roster from a local SQLite database. The app loads player data, matches players to bundled headshot images, and presents the roster in a searchable, filterable list.

## Features

- SwiftUI roster list and player detail screen
- Local SQLite roster loading
- Optional roster database updates from GitHub Pages
- Bundled headshot support
- Search by player name, jersey number, position, or college
- Filter by position and roster status
- Sort by last name or jersey number
- Large jersey-number display in roster rows
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
    Resources/
      browns.db
      headshots/
  BrownsRoster1Tests/
  BrownsRoster1UITests/
  Scripts/
    GetRoster.py
    DownloadHeadshots.py
  docs/
    roster/
      browns.db
      roster_manifest.json
```

## Local Data Files

The app ships with bundled roster resources:

```text
BrownsRoster1/BrownsRoster1/Resources/browns.db
BrownsRoster1/BrownsRoster1/Resources/headshots/
```

On launch, `RosterUpdater` checks the published roster manifest. If the hosted database has a new SHA-256 hash, the app downloads it into Application Support. `RosterLoader.swift` uses that downloaded database first, then falls back to the bundled database.

## Roster Scripts

Run scripts from the repository root:

```bash
cd "/Users/gary/XcodeProjects:BrownsRoster/BrownsRoster1"
```

Fetch the latest Browns roster, build a fresh temporary database, compare it to the current app database, and only install it when roster data changes:

```bash
python3 Scripts/GetRoster.py
```

When a change is found, `GetRoster.py`:

- backs up the previous database into `Backups/`
- installs the new database at `BrownsRoster1/Resources/browns.db`
- publishes `docs/roster/browns.db`
- writes `docs/roster/roster_manifest.json`
- downloads missing headshots
- sends a local macOS notification

For a quiet check without a notification:

```bash
python3 Scripts/GetRoster.py --no-notify
```

To update the bundled database without publishing roster files:

```bash
python3 Scripts/GetRoster.py --skip-publish
```

To download only missing headshots:

```bash
python3 Scripts/DownloadHeadshots.py
```

## Published Roster Updates

The app expects the roster manifest at:

```text
https://garyi113.github.io/BrownsRoster/roster/roster_manifest.json
```

GitHub Pages should be configured to serve the repository's `docs/` folder. After `docs/roster/` is pushed, the app can compare the manifest hash with the local downloaded copy and install the hosted `browns.db` when it changes.

## Running the App

1. Open `BrownsRoster1.xcodeproj` in Xcode.
2. Select the `BrownsRoster1` scheme.
3. Build and run.

If the data files are missing, the app will build, but roster loading or headshot display will not show the complete local data experience.

## TestFlight

The current checkpoint is tagged as:

```text
v1.0.2
```

That corresponds to the TestFlight build `1.0 (2)`.

## Implementation Notes

- `Player.swift` defines the roster model.
- `RosterLoader.swift` opens `browns.db` read-only from Application Support or the app bundle and maps the latest roster snapshot into `Player` values.
- `RosterUpdater` downloads and verifies the published database before installing it locally.
- `ContentView.swift` contains the roster UI, filtering, sorting, searching, row display, detail screen, and launch-time update check.
- Headshots are matched by `imageNumber` and `player.id`, using filenames like `1002_austin-barber.jpg`.
- `GetRoster.py` uses the existing database to preserve image numbering for returning players.

## Requirements

- Xcode
- SwiftUI-compatible Apple platform target
- Python 3
- Python packages: `requests`, `beautifulsoup4`
