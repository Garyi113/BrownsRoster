#!/usr/bin/env python3

import argparse
from pathlib import Path

from GetRoster import (
    default_database_path,
    default_headshots_path,
    full_size_image_url,
    get_roster_page,
    load_existing_image_numbers,
    parse_roster,
)

import requests


def existing_headshot_ids(headshots_path: Path) -> set[str]:
    if not headshots_path.exists():
        return set()

    ids: set[str] = set()
    for image_path in headshots_path.glob("*.jpg"):
        stem_parts = image_path.stem.split("_", 1)
        if len(stem_parts) == 2:
            ids.add(stem_parts[1])

    return ids


def download_missing_headshots(database_path: Path, headshots_path: Path) -> None:
    headshots_path.mkdir(parents=True, exist_ok=True)

    image_numbers = load_existing_image_numbers(database_path)
    html = get_roster_page()
    players = parse_roster(html, image_numbers)
    downloaded_count = 0
    skipped_count = 0
    missing_image_count = 0
    existing_ids = existing_headshot_ids(headshots_path)

    print(f"Found {len(players)} players.")
    print(f"Headshots directory: {headshots_path}\n")

    for index, player in enumerate(players, start=1):
        output_path = headshots_path / player.headshot_file_name

        if output_path.exists() or player.player_id in existing_ids:
            skipped_count += 1
            print(f"[{index}/{len(players)}] skipped     {player.name}")
            continue

        if not player.image_url:
            missing_image_count += 1
            print(f"[{index}/{len(players)}] no image    {player.name}")
            continue

        image_url = full_size_image_url(player.image_url)
        response = requests.get(image_url, timeout=30)
        response.raise_for_status()
        output_path.write_bytes(response.content)
        downloaded_count += 1

        print(f"[{index}/{len(players)}] downloaded  {output_path.name}")

    print()
    print(f"Downloaded: {downloaded_count}")
    print(f"Skipped existing: {skipped_count}")
    print(f"Missing image URL: {missing_image_count}")


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Download Browns roster headshots that are not already stored locally."
    )
    parser.add_argument(
        "--database",
        type=Path,
        default=default_database_path(),
        help="Existing browns.db used to preserve headshot numbering.",
    )
    parser.add_argument(
        "--headshots",
        type=Path,
        default=default_headshots_path(),
        help="Directory containing local headshots.",
    )
    return parser.parse_args()


def main() -> None:
    args = parse_arguments()
    download_missing_headshots(args.database, args.headshots)


if __name__ == "__main__":
    main()
