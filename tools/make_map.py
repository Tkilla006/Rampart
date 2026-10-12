"""Writes data/maps/westlake_intersection.json: the street kit's test intersection as game data.

Same layout as the test scene in tools/art/make_street.py: a four-way intersection, a pocket park,
an alley, and a fenced corner lot at the edge of the Hole. Positions are in tiles (one tile is
32 x 32 ground units, about 1.45 m); props sit at their ground anchor.
"""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "data" / "maps" / "westlake_intersection.json"
N = 15


def grid():
    g = [["sidewalk"] * N for _ in range(N)]
    road = range(6, 11)
    for gx in range(N):
        for gy in range(N):
            in_x, in_y = gy in road, gx in road
            if in_x or in_y:
                g[gy][gx] = "asphalt"
                if in_x and not in_y:
                    g[gy][gx] = "double_yellow_x" if gy == 8 else ("lane_dash_x" if gy in (7, 9) and gx % 3 == 0 else "asphalt")
                if in_y and not in_x:
                    g[gy][gx] = "double_yellow_y" if gx == 8 else ("lane_dash_y" if gx in (7, 9) and gy % 3 == 0 else "asphalt")
    for r in road:
        g[r][5] = "crosswalk_x"; g[r][11] = "crosswalk_x"
        g[5][r] = "crosswalk_y"; g[11][r] = "crosswalk_y"
    g[8][3] = "manhole"; g[7][13] = "asphalt_cracked"; g[13][9] = "asphalt_patched"
    for gx in range(N):
        if gx not in road:
            g[5][gx] = "curb_SW" if gx != 5 else g[5][gx]
            g[11][gx] = "curb_NE" if gx != 11 else g[11][gx]
    for gy in range(N):
        if gy not in road:
            g[gy][5] = "curb_SE" if gy != 5 else g[gy][5]
            g[gy][11] = "curb_NW" if gy != 11 else g[gy][11]
    g[5][5] = g[5][11] = g[11][5] = g[11][11] = "sidewalk"
    g[5][2] = "curb_red_SW"; g[5][3] = "curb_red_SW"; g[11][13] = "storm_drain_NE"
    g[3][13] = "sidewalk_stained"; g[13][2] = "sidewalk_stained"
    for gy in range(12, N):
        for gx in range(12, N):
            g[gy][gx] = ["dirt", "dirt_weeds", "rubble", "rubble_heavy"][(gx * 3 + gy * 5) % 4]
    for gy in range(0, 4):
        for gx in range(0, 4):
            g[gy][gx] = "parkway_grass"
    for gy in range(0, 5):
        g[gy][13] = "alley"; g[gy][14] = "alley"
    return g


# (name, tile x, tile y, blocking radius in ground units; 0 = walk-through)
PROPS = [
    ("palm_tree", 1.5, 4.5, 6), ("palm_tree", 4.5, 1.5, 6), ("palm_tree", 12.2, 4.5, 6),
    ("palm_tree", 4.5, 13.5, 6), ("palm_tree", 14.2, 4.5, 6),
    ("streetlight_r1", 4.6, 4.6, 4), ("streetlight_r3", 11.4, 11.4, 4),
    ("fire_hydrant", 3.2, 5.3, 5), ("bus_bench_r2", 1.9, 4.4, 14), ("trash_can", 12.4, 3.2, 6),
    ("dumpster_r1", 13.6, 1.4, 22),
    ("chainlink_fence_r0", 12.5, 12.1, 0), ("chainlink_fence_r0", 14.5, 12.1, 0),
    ("chainlink_fence_r1", 12.1, 12.5, 0), ("chainlink_fence_r1", 12.1, 13.5, 0), ("chainlink_fence_r1", 12.1, 14.5, 0),
    ("traffic_cone", 13.2, 11.6, 5), ("traffic_cone", 13.9, 11.6, 5), ("traffic_cone", 4.5, 10.4, 5),
]


def main():
    doc = {
        "name": "Westlake intersection",
        "district": "macarthur_park",
        "size": [N, N],
        "tile_units": 32,
        "tiles": grid(),
        "props": [{"name": n, "x": x, "y": y, "radius": r} for n, x, y, r in PROPS],
        # The patrol car, parked at the curb facing northwest. Its footprint is a box in tile units.
        "vehicles": [{"name": "crown_vic", "facing": "NW", "x": 2.6, "y": 10.25,
                      "half_extents": [1.85, 0.7], "interact": "ST-06"}],
        # Walls of the fenced lot at the edge of the Hole: boxes in tile units [x0, y0, x1, y1].
        "blocked": [[12.0, 12.0, 15.0, 15.0]],
        "spawn": {"x": 3.3, "y": 11.45, "facing": "up"},
    }
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(doc, indent=1) + "\n")
    print(f"Wrote {OUT.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
