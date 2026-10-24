#!/usr/bin/env python3
"""Deterministic tests for index generation; never contact XIVAPI."""
import copy
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import update_game_data as builder

SNAPSHOT = {"version": "0123456789abcdef", "patch": "7.57",
            "schema": "exdschema@2:rev:" + "a" * 40}


def fixture_index():
    rows = {}
    for sheet in builder.SHEETS:
        rows[sheet] = {"ids": [4, 3, 1], "names": {
            "en": ["", "", "English name"], "de": ["", "", ""],
            "fr": ["Nom français", "", ""], "ja": ["", "日本語", ""]}}
        if sheet == "Map":
            rows[sheet]["searchTerms"] = {
                lang: [f"{name} Region f1t1/00 {row}" for name, row in zip(names, [4, 3, 1])]
                for lang, names in rows[sheet]["names"].items()}
        if sheet in builder.LEVELS:
            rows[sheet]["levels"] = [40, 30, 10]
    return {"formatVersion": 3, "snapshot": SNAPSHOT.copy(), "rows": rows}



class GeneratorTests(unittest.TestCase):
    def setUp(self):
        self.calls = []

    def get(self, path, parameters=None):
        self.calls.append((path, parameters))
        if path == "version":
            return {"versions": [{"key": SNAPSHOT["version"], "names": ["7.57", "latest"]}]}
        result = {"version": SNAPSHOT["version"], "schema": SNAPSHOT["schema"], "rows": []}
        if not parameters["fields"]:
            return result
        sheet = path.split("/")[1]
        leaf = builder.SHEETS[sheet].split(".")[-1]
        ids = [row for row in range(1, 5) if row > parameters.get("after", 0)][:parameters["limit"]]
        for row in ids:
            names = {f"{leaf}@lang({language})": "" for language in builder.LANGUAGES}
            if row == 1:
                names[f"{leaf}@lang(en)"] = "English name"
            if row == 3:
                names[f"{leaf}@lang(ja)"] = "日本語"
            if row == 4:
                names[f"{leaf}@lang(fr)"] = "Nom français"
            fields = {"ItemResult": {"fields": names}} if sheet == "Recipe" else names
            if sheet == "Map":
                fields = {"Id": "f1t1/00", "PlaceName": {"fields": names},
                          "PlaceNameSub": {"fields": {f"Name@lang({lang})": "" for lang in builder.LANGUAGES}},
                          "PlaceNameRegion": {"fields": {f"Name@lang({lang})": "Region" for lang in builder.LANGUAGES}}}
            if sheet == "Item":
                fields["LevelItem@as(raw)"] = row * 10
            elif sheet == "Recipe":
                fields["RecipeLevelTable"] = {"fields": {"ClassJobLevel": row * 10}}
            elif sheet == "Quest":
                fields["ClassJobLevel"] = [row * 10, 0]
            elif sheet == "Action":
                fields["ClassJobLevel"] = row * 10
            result["rows"].append({"row_id": row, "fields": fields})
        return result

    def test_multilingual_filter_pagination_and_fixed_pins(self):
        with patch.object(builder, "LIMIT", 2):
            result = builder.build(get=self.get)
        self.assertEqual(result, fixture_index())
        pages = [parameters for _, parameters in self.calls if parameters and parameters["fields"]]
        self.assertEqual(len(pages), 18)
        for parameters in pages:
            self.assertEqual(parameters["version"], SNAPSHOT["version"])
            self.assertEqual(parameters["schema"], SNAPSHOT["schema"])

    def test_legacy_index_is_upgraded_and_misaligned_columns_are_rejected(self):
        legacy = {"formatVersion": 1, "snapshot": SNAPSHOT.copy(),
                  "rows": {sheet: [4, 3, 1] for sheet in builder.SHEETS}}
        self.assertEqual(builder.build(legacy, get=self.get), fixture_index())
        for field, value in [("names", {"en": ["bad"]}), ("levels", [1]),
                             ("levels", [-1, 0, 0])]:
            invalid = copy.deepcopy(fixture_index())
            invalid["rows"]["Item"][field] = value
            with self.assertRaises(ValueError):
                builder.validate(invalid)

    def test_format_two_upgrades_to_maps_and_map_titles_include_floors(self):
        legacy = fixture_index()
        legacy["formatVersion"] = 2
        del legacy["rows"]["Map"]
        self.assertEqual(builder.build(legacy, get=self.get), fixture_index())

        def map_rows(path, parameters):
            page = self.get(path, parameters)
            for row in page["rows"]:
                if row["row_id"] == 4:
                    row["fields"]["Id"] = "../00"
                for lang in builder.LANGUAGES:
                    row["fields"]["PlaceNameSub"]["fields"][f"Name@lang({lang})"] = "Upper Floor"
            return page

        maps = builder.build_sheet("Map", SNAPSHOT, map_rows)
        self.assertEqual(maps["ids"], [3, 1])
        self.assertEqual(maps["names"]["en"], ["", "English name · Upper Floor"])
        self.assertEqual(maps["names"]["ja"], ["日本語 · Upper Floor", ""])
        self.assertIn("Upper Floor Region f1t1/00 1", maps["searchTerms"]["en"][1])
        for terms in ({"en": ["bad"]}, {lang: [] for lang in builder.LANGUAGES}):
            invalid = fixture_index()
            invalid["rows"]["Map"]["searchTerms"] = terms
            with self.assertRaises(ValueError):
                builder.validate(invalid)

    def test_unchanged_snapshot_skips_the_scan(self):
        existing = fixture_index()
        self.assertIs(builder.build(existing, get=self.get), existing)
        self.assertEqual(len(self.calls), 2)

    def test_freshness_check_never_scans_or_changes_the_index(self):
        existing = fixture_index()
        original = copy.deepcopy(existing)
        builder.check_latest(existing, get=self.get)
        self.assertEqual(existing, original)
        self.assertEqual(len(self.calls), 2)
        for field, value in [("version", "fedcba9876543210"),
                             ("schema", "exdschema@2:rev:" + "b" * 40)]:
            stale = copy.deepcopy(existing)
            stale["snapshot"][field] = value
            with self.assertRaisesRegex(ValueError, "locally.*commit"):
                builder.check_latest(stale, get=self.get)
            self.assertEqual(stale["snapshot"][field], value)

    def test_mixed_schema_and_nonadvancing_pages_are_rejected(self):
        for failure in ["schema", "pagination"]:
            def broken(path, parameters=None):
                response = self.get(path, parameters)
                if parameters and parameters.get("after"):
                    if failure == "schema":
                        response["schema"] = "exdschema@2:rev:" + "b" * 40
                    else:
                        response["rows"][0]["row_id"] = parameters["after"]
                return response
            with patch.object(builder, "LIMIT", 2), self.assertRaises(ValueError):
                builder.build(get=broken)

    def test_invalid_index_cannot_overwrite_existing_file(self):
        with tempfile.TemporaryDirectory() as directory:
            destination = Path(directory) / "index.json"
            builder.save(fixture_index(), destination)
            original = destination.read_bytes()
            invalid = copy.deepcopy(fixture_index())
            invalid["rows"]["Item"]["ids"] = [4, 4, 1]
            with self.assertRaises(ValueError):
                builder.save(invalid, destination)
            self.assertEqual(destination.read_bytes(), original)
            self.assertEqual(json.loads(original), fixture_index())
            self.assertEqual(destination.stat().st_mode & 0o777, 0o644)
            self.assertEqual(list(Path(directory).iterdir()), [destination])


if __name__ == "__main__":
    unittest.main()
