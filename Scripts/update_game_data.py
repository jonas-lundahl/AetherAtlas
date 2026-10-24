#!/usr/bin/env python3
"""Build the release's pinned, multilingual browsing and sorting index. Requires Python 3 and macOS curl."""
import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
from urllib.parse import urlencode

ROOT = Path(__file__).resolve().parent.parent
DESTINATION = ROOT / "Sources/AetherCore/Resources/GameDataIndex.json"
SHEETS = {"Item": "Name", "Recipe": "ItemResult.Name", "Quest": "Name",
          "ENpcResident": "Singular", "Action": "Name", "Map": "PlaceName.Name"}
LANGUAGES = ("en", "de", "fr", "ja")
FORMAT_VERSION = 3
LEVELS = {"Item": "LevelItem@as(raw)", "Recipe": "RecipeLevelTable.ClassJobLevel",
          "Quest": "ClassJobLevel", "Action": "ClassJobLevel"}
LIMIT = 500


def fetch(path, parameters=None):
    url = "https://v2.xivapi.com/api/" + path
    if parameters:
        url += "?" + urlencode(parameters)
    # Use the OS trust store; no credentials, TLS overrides, or automatic retries.
    data = subprocess.check_output([
        "/usr/bin/curl", "--fail", "--silent", "--show-error", "--compressed",
        "--max-time", "30", "--user-agent", "AetherAtlas-IndexBuilder/1.0", url,
    ])
    return json.loads(data)


def validate(index):
    snapshot = index["snapshot"]
    if (index["formatVersion"] != FORMAT_VERSION
            or not re.fullmatch(r"[a-f0-9]{16}", snapshot["version"])
            or not re.fullmatch(r"exdschema@2:rev:[a-f0-9]{40}", snapshot["schema"])
            or not re.fullmatch(r"[0-9]+\.[0-9]+(x[0-9]+)?", snapshot["patch"])
            or set(index["rows"]) != set(SHEETS)):
        raise ValueError("Invalid index manifest")
    for sheet, row in index["rows"].items():
        ids = row["ids"]
        names = row["names"]
        if (not ids or len(ids) > 1_000_000
                or any(type(value) is not int or not 0 <= value <= 0xFFFFFFFF for value in ids)
                or any(a <= b for a, b in zip(ids, ids[1:]))
                or set(names) != set(LANGUAGES)
                or any(len(values) != len(ids) for values in names.values())
                or any(not isinstance(name, str) or len(name.encode("utf-8")) > 4096
                       for values in names.values() for name in values)
                or any(not any(names[lang][i].strip() for lang in LANGUAGES)
                       for i in range(len(ids)))):
            raise ValueError(f"Invalid index rows for {sheet}")
        if sheet == "Map":
            terms = row.get("searchTerms", {})
            if (set(terms) != set(LANGUAGES)
                    or any(len(values) != len(ids) for values in terms.values())
                    or any(not isinstance(value, str) or len(value.encode("utf-8")) > 16384
                           for values in terms.values() for value in values)):
                raise ValueError("Invalid map search terms")
        if sheet in LEVELS:
            levels = row["levels"]
            if (len(levels) != len(ids)
                    or any(type(level) is not int or not 0 <= level <= 0xFFFFFFFF for level in levels)):
                raise ValueError(f"Invalid levels for {sheet}")
        elif "levels" in row:
            raise ValueError(f"Unexpected levels for {sheet}")
    return index


def latest_snapshot(get=fetch):
    latest = next(v for v in get("version")["versions"] if "latest" in v["names"])
    patch = next(name for name in latest["names"] if name != "latest")
    probe = get("sheet/Item", {"version": latest["key"], "fields": "", "transient": "", "limit": 1})
    if probe["version"] != latest["key"]:
        raise ValueError("Dataset changed during version discovery")
    return {"version": latest["key"], "patch": patch, "schema": probe["schema"]}


def check_latest(index, get=fetch):
    validate(index)
    latest = latest_snapshot(get)
    if index["snapshot"] != latest:
        raise ValueError(
            f"The committed index pins are out of date (bundled patch {index['snapshot']['patch']}; "
            f"XIVAPI latest patch {latest['patch']}). Run 'python3 Scripts/update_game_data.py' "
            "locally, review the dataset/schema change, and commit GameDataIndex.json before releasing.")
    print(f"Committed index matches XIVAPI: patch {latest['patch']}", flush=True)


def build(existing=None, get=fetch, force=False):
    snapshot = latest_snapshot(get)
    patch = snapshot["patch"]
    if (existing is not None and not force and existing.get("formatVersion") == FORMAT_VERSION
            and validate(existing)["snapshot"] == snapshot):
        print(f"Bundled game data is current: patch {patch}", flush=True)
        return existing
    rows = {sheet: build_sheet(sheet, snapshot, get) for sheet in SHEETS}
    return validate({"formatVersion": FORMAT_VERSION, "snapshot": snapshot, "rows": rows})


def build_sheet(sheet, snapshot, get=fetch):
    name_field = SHEETS[sheet]
    ids = []
    all_names = {lang: [] for lang in LANGUAGES}
    search_terms = {lang: [] for lang in LANGUAGES}
    levels = []
    after = None
    parameters = {"version": snapshot["version"], "schema": snapshot["schema"],
                  "fields": ",".join(f"{name_field}@lang({lang})" for lang in LANGUAGES),
                  "transient": "", "limit": LIMIT}
    if sheet in LEVELS:
        parameters["fields"] += "," + LEVELS[sheet]
    if sheet == "Map":
        parameters["fields"] += ",Id," + ",".join(
            f"{field}.Name@lang({lang})" for field in ("PlaceNameSub", "PlaceNameRegion") for lang in LANGUAGES)
    while True:
        page = get(f"sheet/{sheet}", parameters.copy())
        if page["version"] != snapshot["version"] or page["schema"] != snapshot["schema"]:
            raise ValueError(f"Dataset/schema mismatch while scanning {sheet}")
        for row in page["rows"]:
            row_id = row["row_id"]
            if type(row_id) is not int or row_id < 0 or (after is not None and row_id <= after):
                raise ValueError(f"Pagination did not advance in {sheet}")
            after = row_id
            fields = row["fields"]
            if sheet in ("Recipe", "Map"):
                fields = fields[name_field.split(".")[0]]["fields"]
            leaf = name_field.split(".")[-1]
            names = [fields[f"{leaf}@lang({lang})"] for lang in LANGUAGES]
            if not all(isinstance(name, str) for name in names):
                raise ValueError(f"Invalid name projection for {sheet}:{row_id}")
            if sheet == "Map":
                raw = row["fields"]
                asset = raw["Id"]
                if not isinstance(asset, str) or not re.fullmatch(r"[A-Za-z0-9]+/[0-9]{2}", asset):
                    continue
                for i, lang in enumerate(LANGUAGES):
                    floor = raw["PlaceNameSub"]["fields"][f"Name@lang({lang})"]
                    if names[i].strip() and floor:
                        names[i] += " · " + floor
            if any(name.strip() for name in names):
                ids.append(row_id)
                for lang, name in zip(LANGUAGES, names):
                    all_names[lang].append(name)
                    if sheet == "Map":
                        region = raw["PlaceNameRegion"]["fields"][f"Name@lang({lang})"]
                        search_terms[lang].append(f"{name} {region} {asset} {row_id}")
                if sheet in LEVELS:
                    raw = row["fields"]
                    level = (raw["LevelItem@as(raw)"] if sheet == "Item" else
                             raw["RecipeLevelTable"]["fields"]["ClassJobLevel"] if sheet == "Recipe" else
                             raw["ClassJobLevel"][0] if sheet == "Quest" else raw["ClassJobLevel"])
                    levels.append(level)
        if not page["rows"]:
            break
        parameters["after"] = after
    result = {"ids": list(reversed(ids)),
              "names": {lang: list(reversed(values)) for lang, values in all_names.items()}}
    if sheet in LEVELS:
        result["levels"] = list(reversed(levels))
    if sheet == "Map":
        result["searchTerms"] = {lang: list(reversed(values)) for lang, values in search_terms.items()}
    print(f"{sheet}: {len(ids):,} named IDs (patch {snapshot['patch']})", flush=True)
    return result


def save(index, destination):
    data = (json.dumps(validate(index), sort_keys=True, ensure_ascii=False, separators=(",", ":")) + "\n").encode()
    destination.parent.mkdir(parents=True, exist_ok=True)
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(dir=destination.parent, delete=False) as output:
            temporary = Path(output.name)
            os.fchmod(output.fileno(), 0o644)
            output.write(data)
        os.replace(temporary, destination)
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)
    print(f"Saved {len(data):,} bytes to {destination}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--check", action="store_true", help="Validate the checked-in index offline")
    mode.add_argument("--check-latest", action="store_true", help="Compare pins with XIVAPI; never rebuild")
    mode.add_argument("--force", action="store_true", help="Rebuild even if the pins are unchanged")
    args = parser.parse_args()
    existing = json.loads(DESTINATION.read_bytes()) if DESTINATION.exists() else None
    if args.check or args.check_latest:
        if existing is None:
            raise ValueError("Bundled index is missing")
        validate(existing)
        if args.check_latest:
            check_latest(existing)
        else:
            print(f"Valid bundled index: patch {existing['snapshot']['patch']}")
        return
    updated = build(existing, force=args.force)
    if updated != existing:
        save(updated, DESTINATION)


if __name__ == "__main__":
    main()
