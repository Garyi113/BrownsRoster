#!/usr/bin/env python3

import argparse
import hashlib
import json
import re
import shutil
import sqlite3
import subprocess
import tempfile
from dataclasses import dataclass
from datetime import date, datetime
from pathlib import Path
from typing import Optional
from urllib.parse import urljoin, urlparse

import requests
from bs4 import BeautifulSoup


ROSTER_URL = "https://www.clevelandbrowns.com/team/players-roster/"
BASE_URL = "https://www.clevelandbrowns.com"
DEFAULT_PUBLIC_BASE_URL = "https://garyi113.github.io/BrownsRoster/roster"


@dataclass
class Player:
    player_id: str
    name: str
    number: str
    position: str
    height: str
    weight: str
    age: str
    experience: str
    college: str
    roster_status: str
    profile_url: str
    image_url: str
    image_number: int

    @property
    def headshot_file_name(self) -> str:
        return f"{self.image_number}_{self.player_id}.jpg"


def project_root() -> Path:
    return Path(__file__).resolve().parents[1]


def default_database_path() -> Path:
    return project_root() / "BrownsRoster1" / "Resources" / "browns.db"


def default_headshots_path() -> Path:
    return project_root() / "BrownsRoster1" / "Resources" / "headshots"


def default_backup_path() -> Path:
    return project_root() / "Backups"


def default_publish_path() -> Path:
    return project_root() / "docs" / "roster"


def get_roster_page() -> str:
    headers = {
        "User-Agent": (
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
            "AppleWebKit/537.36 (KHTML, like Gecko) "
            "Chrome/130.0.0.0 Safari/537.36"
        )
    }
    response = requests.get(ROSTER_URL, headers=headers, timeout=30)
    response.raise_for_status()
    return response.text


def slugify(value: str) -> str:
    value = value.lower().strip()
    value = value.replace("'", "")
    value = re.sub(r"[^a-z0-9]+", "-", value)
    return value.strip("-")


def player_id_from_profile_url(profile_url: str, name: str) -> str:
    path = urlparse(profile_url).path.rstrip("/")
    player_id = path.split("/")[-1]
    return slugify(player_id or name)


def normalize_url(value: str) -> str:
    if not value:
        return ""
    return urljoin(BASE_URL, value)


def full_size_image_url(image_url: str) -> str:
    if not image_url:
        return ""
    return (
        image_url
        .replace("/t_thumb_squared/", "/")
        .replace("/t_lazy/", "/")
    )


def load_existing_image_numbers(database_path: Path) -> dict[str, int]:
    if not database_path.exists():
        return {}

    with sqlite3.connect(database_path) as connection:
        try:
            rows = connection.execute(
                """
                SELECT player_id, image_number
                FROM players
                WHERE image_number IS NOT NULL
                """
            ).fetchall()
        except sqlite3.DatabaseError:
            return {}

    return {player_id: image_number for player_id, image_number in rows}


def next_image_number(existing_numbers: dict[str, int]) -> int:
    return max(existing_numbers.values(), default=1000) + 1


def parse_roster(html: str, image_numbers: dict[str, int]) -> list[Player]:
    soup = BeautifulSoup(html, "html.parser")
    players: list[Player] = []
    next_number = next_image_number(image_numbers)

    for table in soup.find_all("table", summary="Roster"):
        caption = table.find("caption")
        roster_status = caption.get_text(" ", strip=True) if caption else ""

        for row in table.find_all("tr"):
            cells = row.find_all("td")
            if len(cells) != 8:
                continue

            name = cells[0].get_text(" ", strip=True)
            if not name:
                continue

            link = cells[0].find("a", href=True)
            profile_url = normalize_url(link["href"]) if link else ""
            player_id = player_id_from_profile_url(profile_url, name)

            image = cells[0].find("img")
            image_url = ""
            if image:
                image_url = image.get("src") or image.get("data-src") or ""

            if player_id not in image_numbers:
                image_numbers[player_id] = next_number
                next_number += 1

            players.append(
                Player(
                    player_id=player_id,
                    name=name,
                    number=cells[1].get_text(" ", strip=True),
                    position=cells[2].get_text(" ", strip=True),
                    height=cells[3].get_text(" ", strip=True),
                    weight=cells[4].get_text(" ", strip=True),
                    age=cells[5].get_text(" ", strip=True),
                    experience=cells[6].get_text(" ", strip=True),
                    college=cells[7].get_text(" ", strip=True),
                    roster_status=roster_status,
                    profile_url=profile_url,
                    image_url=normalize_url(image_url),
                    image_number=image_numbers[player_id],
                )
            )

    return players


def create_schema(connection: sqlite3.Connection) -> None:
    connection.executescript(
        """
        DROP TABLE IF EXISTS roster_history;
        DROP TABLE IF EXISTS players;

        CREATE TABLE players (
            player_id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            profile_url TEXT NOT NULL,
            image_url TEXT,
            image_number INTEGER
        );

        CREATE TABLE roster_history (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            player_id TEXT NOT NULL,
            snapshot_date TEXT NOT NULL,
            number TEXT,
            position TEXT,
            height TEXT,
            weight TEXT,
            age TEXT,
            experience TEXT,
            college TEXT,
            roster_status TEXT,

            FOREIGN KEY (player_id)
                REFERENCES players(player_id),

            UNIQUE (player_id, snapshot_date)
        );
        """
    )


def write_database(players: list[Player], database_path: Path, snapshot_date: str) -> None:
    database_path.parent.mkdir(parents=True, exist_ok=True)

    with sqlite3.connect(database_path) as connection:
        create_schema(connection)

        connection.executemany(
            """
            INSERT INTO players (
                player_id,
                name,
                profile_url,
                image_url,
                image_number
            )
            VALUES (?, ?, ?, ?, ?)
            """,
            [
                (
                    player.player_id,
                    player.name,
                    player.profile_url,
                    player.image_url,
                    player.image_number,
                )
                for player in players
            ],
        )

        connection.executemany(
            """
            INSERT INTO roster_history (
                player_id,
                snapshot_date,
                number,
                position,
                height,
                weight,
                age,
                experience,
                college,
                roster_status
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            [
                (
                    player.player_id,
                    snapshot_date,
                    player.number,
                    player.position,
                    player.height,
                    player.weight,
                    player.age,
                    player.experience,
                    player.college,
                    player.roster_status,
                )
                for player in players
            ],
        )


def database_signature(database_path: Path) -> Optional[tuple[list[tuple], list[tuple]]]:
    if not database_path.exists():
        return None

    with sqlite3.connect(database_path) as connection:
        try:
            players = connection.execute(
                """
                SELECT player_id, name, profile_url, image_url, image_number
                FROM players
                ORDER BY player_id
                """
            ).fetchall()

            roster = connection.execute(
                """
                SELECT
                    player_id,
                    number,
                    position,
                    height,
                    weight,
                    age,
                    experience,
                    college,
                    roster_status
                FROM roster_history
                ORDER BY player_id
                """
            ).fetchall()
        except sqlite3.DatabaseError:
            return None

    return players, roster


def databases_match(current_database: Path, new_database: Path) -> bool:
    current_signature = database_signature(current_database)
    new_signature = database_signature(new_database)
    return current_signature is not None and current_signature == new_signature


def backup_database(database_path: Path, backup_directory: Path) -> Optional[Path]:
    if not database_path.exists():
        return None

    backup_directory.mkdir(parents=True, exist_ok=True)
    timestamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    backup_path = backup_directory / f"{database_path.stem}-{timestamp}{database_path.suffix}"
    shutil.copy2(database_path, backup_path)
    return backup_path


def install_database(new_database: Path, database_path: Path) -> None:
    database_path.parent.mkdir(parents=True, exist_ok=True)
    shutil.move(str(new_database), str(database_path))


def file_sha256(file_path: Path) -> str:
    digest = hashlib.sha256()
    with file_path.open("rb") as file:
        for chunk in iter(lambda: file.read(1024 * 1024), b""):
            digest.update(chunk)

    return digest.hexdigest()


def database_player_count(database_path: Path) -> int:
    with sqlite3.connect(database_path) as connection:
        return connection.execute("SELECT COUNT(*) FROM players").fetchone()[0]


def remove_test_players(database_path: Path, drop_count: int) -> list[str]:
    if drop_count <= 0:
        return []

    with sqlite3.connect(database_path) as connection:
        players_to_remove = connection.execute(
            """
            SELECT player_id
            FROM players
            ORDER BY name DESC
            LIMIT ?
            """,
            (drop_count,),
        ).fetchall()

        player_ids = [row[0] for row in players_to_remove]
        if not player_ids:
            return []

        connection.executemany(
            "DELETE FROM roster_history WHERE player_id = ?",
            [(player_id,) for player_id in player_ids],
        )
        connection.executemany(
            "DELETE FROM players WHERE player_id = ?",
            [(player_id,) for player_id in player_ids],
        )
        connection.commit()

    return player_ids


def publish_database(
    database_path: Path,
    publish_directory: Path,
    public_base_url: str,
    snapshot_date: str,
    player_count: int,
    test_drop_count: int = 0,
) -> Path:
    publish_directory.mkdir(parents=True, exist_ok=True)

    published_database = publish_directory / database_path.name
    shutil.copy2(database_path, published_database)
    removed_test_player_ids = remove_test_players(published_database, test_drop_count)
    published_player_count = database_player_count(published_database)

    manifest = {
        "version": (
            f"{snapshot_date}-test-minus-{len(removed_test_player_ids)}"
            if removed_test_player_ids
            else snapshot_date
        ),
        "updatedAt": datetime.now().astimezone().isoformat(timespec="seconds"),
        "playerCount": published_player_count,
        "sha256": file_sha256(published_database),
        "databaseUrl": f"{public_base_url.rstrip('/')}/{database_path.name}",
    }

    manifest_path = publish_directory / "roster_manifest.json"
    manifest_path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")

    if removed_test_player_ids:
        print(
            "Published test roster database with "
            f"{len(removed_test_player_ids)} players removed from the hosted copy."
        )

    return manifest_path


def send_notification(title: str, message: str) -> None:
    script = f'display notification "{message}" with title "{title}"'
    try:
        subprocess.run(["osascript", "-e", script], check=False)
    except OSError:
        pass


def download_headshots(players: list[Player], headshots_path: Path) -> None:
    headshots_path.mkdir(parents=True, exist_ok=True)

    for player in players:
        if not player.image_url:
            continue

        output_path = headshots_path / player.headshot_file_name
        if output_path.exists():
            continue

        image_url = full_size_image_url(player.image_url)
        response = requests.get(image_url, timeout=30)
        response.raise_for_status()
        output_path.write_bytes(response.content)


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Fetch the latest Cleveland Browns roster and write browns.db."
    )
    parser.add_argument(
        "--database",
        type=Path,
        default=default_database_path(),
        help="Path to write the SQLite database.",
    )
    parser.add_argument(
        "--headshots",
        type=Path,
        default=default_headshots_path(),
        help="Directory to write downloaded headshots.",
    )
    parser.add_argument(
        "--snapshot-date",
        default=date.today().isoformat(),
        help="Snapshot date to store in roster_history.",
    )
    parser.add_argument(
        "--backup-directory",
        type=Path,
        default=default_backup_path(),
        help="Directory where the previous database is saved when roster data changes.",
    )
    parser.add_argument(
        "--publish-directory",
        type=Path,
        default=default_publish_path(),
        help="Directory where browns.db and roster_manifest.json are published for GitHub Pages.",
    )
    parser.add_argument(
        "--public-base-url",
        default=DEFAULT_PUBLIC_BASE_URL,
        help="Public URL prefix where published roster files will be hosted.",
    )
    parser.add_argument(
        "--skip-headshots",
        action="store_true",
        help="Write the database without downloading missing headshots.",
    )
    parser.add_argument(
        "--skip-publish",
        action="store_true",
        help="Do not copy browns.db or write roster_manifest.json into the publish directory.",
    )
    parser.add_argument(
        "--publish-test-drop-count",
        type=int,
        default=0,
        help=(
            "Test only: remove this many players from the published database copy "
            "without changing the bundled app database."
        ),
    )
    parser.add_argument(
        "--force",
        action="store_true",
        help="Install the newly generated database even when no roster difference is found.",
    )
    parser.add_argument(
        "--no-notify",
        action="store_true",
        help="Do not send a local macOS notification.",
    )
    return parser.parse_args()


def main() -> None:
    args = parse_arguments()

    image_numbers = load_existing_image_numbers(args.database)
    html = get_roster_page()
    players = parse_roster(html, image_numbers)

    if not players:
        raise RuntimeError("No players were found on the Browns roster page.")

    with tempfile.TemporaryDirectory() as temporary_directory:
        new_database = Path(temporary_directory) / args.database.name
        write_database(players, new_database, args.snapshot_date)

        has_changed = not databases_match(args.database, new_database)
        should_install = has_changed or args.force

        if should_install:
            backup_path = backup_database(args.database, args.backup_directory)
            install_database(new_database, args.database)

            print(f"Installed updated database: {args.database}")
            if backup_path:
                print(f"Saved previous database: {backup_path}")
            else:
                print("No previous database existed, so no backup was created.")

            if not args.no_notify:
                send_notification(
                    "Browns roster updated",
                    f"Installed a fresh roster database with {len(players)} players.",
                )
        else:
            print("No roster changes found. Existing database was left in place.")

            if not args.no_notify:
                send_notification(
                    "Browns roster unchanged",
                    f"Checked {len(players)} players. No database update needed.",
                )

    if not args.skip_publish:
        manifest_path = publish_database(
            args.database,
            args.publish_directory,
            args.public_base_url,
            args.snapshot_date,
            len(players),
            args.publish_test_drop_count,
        )
        print(f"Published roster database: {args.publish_directory / args.database.name}")
        print(f"Published manifest: {manifest_path}")

    if not args.skip_headshots:
        download_headshots(players, args.headshots)

    print(f"Checked {len(players)} players from the Browns roster page.")
    if not args.skip_headshots:
        print(f"Headshots directory: {args.headshots}")


if __name__ == "__main__":
    main()
