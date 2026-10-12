"""Writes art/tiles/rampart_battle_tileset.tres: street tiles (source 0) and interior floors (source 1)."""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
street = json.loads((ROOT / "data/art/rampart_street_tiles_index.json").read_text())
interior = json.loads((ROOT / "data/art/rampart_interior_tiles_index.json").read_text())
lines = ['[gd_resource type="TileSet" load_steps=5 format=3]', "",
         '[ext_resource type="Texture2D" path="res://art/tiles/rampart_street_tiles.png" id="1_street"]',
         '[ext_resource type="Texture2D" path="res://art/tiles/rampart_interior_tiles.png" id="2_interior"]', ""]
for sid, (tex, index) in enumerate((("1_street", street), ("2_interior", interior))):
    lines += [f'[sub_resource type="TileSetAtlasSource" id="TileSetAtlasSource_{sid}"]', f'texture = ExtResource("{tex}")',
              "texture_region_size = Vector2i(64, 32)"]
    lines += [f"{c}:{r}/0 = 0" for c, r in index.values()]
    lines.append("")
lines += ["[resource]", "tile_shape = 1", "tile_layout = 5", "tile_size = Vector2i(64, 32)",
          'sources/0 = SubResource("TileSetAtlasSource_0")', 'sources/1 = SubResource("TileSetAtlasSource_1")', ""]
(ROOT / "art/tiles/rampart_battle_tileset.tres").write_text("\n".join(lines))
print("Wrote art/tiles/rampart_battle_tileset.tres")
