#!/usr/bin/env python3
"""Dev verification tool for Mouse-Hunter MVP levels.

Mirrors the board-space rotation/placement math used by placement_validator.gd:
- 90-degree clockwise rotation in a y-down grid: (x, y) -> (-y, x)
- normalization translates the rotated cells so the minimum corner is (0, 0)

Enumerates every full tiling of the board with the six pieces, then designs
three levels whose mice are subsets of a chosen tiling's opening cells and
reports how many solutions satisfy each level (solvability check).

Run:  python3 tests/level_solver.py
Writes: tests/solutions.json (used by tests/smoke_test.gd)
"""
import json
import os
import sys

# ---------------------------------------------------------------------------
# Piece data (mirrors res://data/pieces/*.tres)
# ---------------------------------------------------------------------------
PIECES = {
    "square": {"cells": [(0, 0), (1, 0), (0, 1), (1, 1)], "opening": (0, 0)},
    "plank":  {"cells": [(0, 0), (0, 1), (0, 2), (0, 3)], "opening": (0, 1)},
    "corner": {"cells": [(0, 0), (0, 1), (0, 2), (1, 2)], "opening": (0, 1)},
    "hook":   {"cells": [(0, 0), (0, 1), (0, 2), (1, 0)], "opening": (1, 0)},
    "step":   {"cells": [(0, 0), (1, 0), (1, 1), (2, 1)], "opening": (1, 1)},
    "skew":   {"cells": [(0, 1), (1, 1), (1, 0), (2, 0)], "opening": (1, 1)},
}
# All six are checkerboard-balanced (the T tetromino is not, and a single
# imbalanced piece can never tile an even-area rectangle), so this set can
# fully tile the 4x6 board. "corner" (L) / "hook" (J) and "step" (Z) /
# "skew" (S) are distinct one-sided shapes under rotation-only rules.
BOARD_W, BOARD_H = 4, 6


def rotate_cw(cell, times):
    x, y = cell
    for _ in range(times % 4):
        x, y = -y, x
    return x, y


def rotated_variant(piece, rotation):
    """Return (normalized cells, normalized opening) for a rotation step."""
    cells = [rotate_cw(c, rotation) for c in piece["cells"]]
    min_x = min(c[0] for c in cells)
    min_y = min(c[1] for c in cells)
    cells = [(c[0] - min_x, c[1] - min_y) for c in cells]
    opening = rotate_cw(piece["opening"], rotation)
    opening = (opening[0] - min_x, opening[1] - min_y)
    return tuple(cells), opening


def all_variants(piece):
    """Deduplicated (cells, opening) variants across the 4 rotations."""
    seen = set()
    out = []
    for r in range(4):
        v = rotated_variant(piece, r)
        if v not in seen:
            seen.add(v)
            out.append(v)
    return out


def enumerate_tilings():
    """All full tilings of BOARD_W x BOARD_H with every piece used once."""
    piece_ids = sorted(PIECES)
    board_cells = [(x, y) for y in range(BOARD_H) for x in range(BOARD_W)]

    moves_by_cell = {c: [] for c in board_cells}
    for pid in piece_ids:
        for cells, opening in all_variants(PIECES[pid]):
            w = max(c[0] for c in cells) + 1
            h = max(c[1] for c in cells) + 1
            for ox in range(BOARD_W - w + 1):
                for oy in range(BOARD_H - h + 1):
                    world = tuple((ox + cx, oy + cy) for cx, cy in cells)
                    wopen = (ox + opening[0], oy + opening[1])
                    for c in world:
                        moves_by_cell[c].append((pid, world, wopen))

    solutions = []
    used = {}
    used_pieces = set()

    def dfs():
        first = None
        for c in board_cells:
            if c not in used:
                first = c
                break
        if first is None:
            openings = frozenset(p[2] for p in used.values())
            solutions.append({
                "placements": {pid: (cells, wopen)
                               for pid, cells, wopen in used.values()},
                "openings": openings,
            })
            return
        for pid, world, wopen in moves_by_cell[first]:
            if pid in used_pieces:
                continue
            if any(c in used for c in world):
                continue
            used_pieces.add(pid)
            for c in world:
                used[c] = (pid, world, wopen)
            dfs()
            for c in world:
                del used[c]
            used_pieces.remove(pid)

    dfs()
    return solutions


def count_solutions_for_mice(tilings, mice):
    mice = set(mice)
    return sum(1 for t in tilings if mice.issubset(t["openings"]))


def _best_mice_subset(tilings, k):
    """Pick the k-mice subset of some tiling's openings that keeps the
    level easiest (most satisfying solutions), for a friendly ramp."""
    from itertools import combinations
    best_mice = None
    best_tiling = None
    best_n = -1
    for t in tilings:
        for mice in combinations(sorted(t["openings"]), k):
            n = count_solutions_for_mice(tilings, mice)
            if n > best_n:
                best_n = n
                best_mice = list(mice)
                best_tiling = t
    return best_mice, best_tiling, best_n




def main():
    tilings = enumerate_tilings()
    print(f"Board {BOARD_W}x{BOARD_H}, {len(PIECES)} pieces x 4 cells = "
          f"{len(PIECES) * 4} cells (board has {BOARD_W * BOARD_H})")
    print(f"Total full tilings: {len(tilings)}")
    if not tilings:
        print("ERROR: piece set cannot tile the board -- redesign pieces.")
        return 1

    opening_sets = sorted(set(t["openings"] for t in tilings))
    print(f"Distinct opening-cell sets across tilings: {len(opening_sets)}")

    out = {"board_size": [BOARD_W, BOARD_H], "levels": []}
    # Difficulty ramp via solution count:
    #   level 1: 3 mice (many solutions) -> level 2: 5 mice (few)
    #   -> level 3: 6 mice (unique solution).
    l1_mice, l1_tiling, l1_n = _best_mice_subset(tilings, 3)
    l2_mice, l2_tiling, l2_n = _best_mice_subset(tilings, 5)
    # Level 3 uses all 6 opening cells; pick a tiling whose mice positions
    # differ the most from level 2 to keep the levels visually distinct.
    l2_cells = set(l2_mice)
    l3_tiling = min(tilings, key=lambda t: len(t["openings"] & l2_cells))
    l3_mice = sorted(l3_tiling["openings"])
    l3_n = count_solutions_for_mice(tilings, l3_mice)
    level_specs = [
        {"id": "kitchen_001", "room": "kitchen",
         "mice": l1_mice, "tiling": l1_tiling, "n": l1_n},
        {"id": "living_room_002", "room": "living_room",
         "mice": l2_mice, "tiling": l2_tiling, "n": l2_n},
        {"id": "bedroom_003", "room": "bedroom",
         "mice": l3_mice, "tiling": l3_tiling, "n": l3_n},
    ]
    ok = True
    for spec in level_specs:
        t = spec["tiling"]
        mice = list(spec["mice"])
        n = spec["n"]
        print(f"\nLevel {spec['id']} ({spec['room']}): mice={mice} "
              f"-> {n} satisfying solutions")
        if n == 0:
            print("  ERROR: level is not solvable!")
            ok = False
        rotations = {}
        for pid, (cells, wopen) in t["placements"].items():
            minx = min(c[0] for c in cells)
            miny = min(c[1] for c in cells)
            norm = tuple(sorted((c[0] - minx, c[1] - miny) for c in cells))
            for r in range(4):
                rc, _ = rotated_variant(PIECES[pid], r)
                if tuple(sorted(rc)) == norm:
                    rotations[pid] = r
                    break
        out["levels"].append({
            "id": spec["id"], "room": spec["room"], "mice": mice,
            "placements": {pid: [list(c) for c in data[0]]
                           for pid, data in t["placements"].items()},
            "rotations": rotations,
        })

    if not ok:
        return 1

    path = os.path.join(os.path.dirname(__file__), "solutions.json")
    with open(path, "w") as f:
        json.dump(out, f, indent=2)
    print(f"\nWrote {path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
