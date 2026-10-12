#!/usr/bin/env bash
# Regenerates every procedural art asset and copies it into the Godot project.
# Needs Python 3 with Pillow, numpy and scipy.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ART="$ROOT/tools/art"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

python3 "$ART/make_rookie.py" "$TMP/rookie"
python3 "$ART/make_portrait_hd.py" "$TMP/portraits"
python3 "$ART/make_crownvic.py" "$TMP/car" > /dev/null
python3 "$ART/make_street.py" "$TMP/street" "$TMP/car" "$TMP/rookie/rookie_officer.png"
(cd "$ART" && python3 make_buildings.py "$TMP/buildings")
(cd "$ART" && python3 make_people.py "$TMP/people" "$TMP/rookie/rookie_officer.png")

mkdir -p "$ROOT"/art/{characters/portraits,characters/people,tiles,props,vehicles,walls} "$ROOT/data/art" "$ROOT/docs/art"

cp "$TMP/rookie/rookie_officer.png" "$TMP/rookie/rookie_officer_frames.tres" "$ROOT/art/characters/"
cp "$TMP"/portraits/rookie_portrait_{neutral,smile,angry,sad,surprised,shaken,tired}.png "$ROOT/art/characters/portraits/"
cp "$TMP/street/rampart_street_tiles.png" "$TMP/street/rampart_street_tileset.tres" "$ROOT/art/tiles/"
cp "$TMP"/street/props/*.png "$ROOT/art/props/"
cp "$TMP"/car/crown_vic_*.png "$ROOT/art/vehicles/"
cp "$TMP/street/rampart_street_tiles_index.json" "$TMP/street/props_anchors.json" "$TMP/car/crown_vic_anchors.json" "$ROOT/data/art/"

# Tactical art: walls on tile edges, interior floors, store props, civilian sedans, people.
cp "$TMP"/buildings/walls/*.png "$ROOT/art/walls/"
cp "$TMP"/buildings/props/*.png "$ROOT/art/props/"
cp "$TMP"/buildings/cars/*.png "$ROOT/art/vehicles/"
cp "$TMP/buildings/rampart_interior_tiles.png" "$ROOT/art/tiles/"
cp "$TMP/buildings/walls_anchors.json" "$TMP/buildings/objects_anchors.json" "$TMP/buildings/sedan_anchors.json" \
   "$TMP/buildings/rampart_interior_tiles_index.json" "$ROOT/data/art/"
cp "$TMP"/people/*.png "$TMP"/people/*.tres "$ROOT/art/characters/people/"
cp "$TMP/people/people_index.json" "$ROOT/data/art/"
python3 "$ROOT/tools/make_battle_tileset.py"

# Reference renders for the docs, kept out of the Godot import.
cp "$TMP/rookie/rookie_officer_preview.png" "$TMP/rookie/rookie_officer_walk.gif" \
   "$TMP"/portraits/rookie_portraits_preview_{1,2}.png "$TMP/portraits/rookie_portrait_closeup.png" \
   "$TMP/street/rampart_test_scene.png" "$TMP/street/rampart_tiles_preview.png" "$ROOT/docs/art/"
echo "Art rebuilt."
