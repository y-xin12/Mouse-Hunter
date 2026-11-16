#!/usr/bin/env python3
"""Dev verification tool for Mouse-Hunter MVP levels.

Mirrors the board-space rotation/placement math used by placement_validator.gd:
- 90-degree clockwise rotation in a y-down grid: (x, y) -> (-y, x)
- normalization translates the rotated cells so the minimum corner is (0, 0)

Enumerates every full tiling of the board with the six pieces, then designs
five levels whose mice are subsets of a chosen tiling's opening cells and
reports how many solutions satisfy each level (solvability check). Levels 4-5
are designed so every satisfying tiling needs at least one piece rotated --
they cannot be won without using the rotation mechanic.

Each level also receives wall hints: edges between cells that no single piece
may cross (walls never occupy cells and never change the tiling area). Walls
are picked from the reference tiling's internal boundaries, mouse-adjacent
edges first, so every hint stays truthful and the solution stays valid.

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


def count_solutions_for_mice(tilings, mice, walls=None):
    mice = set(mice)
    count = 0
    for t in tilings:
        if not mice.issubset(t["openings"]):
            continue
        if walls and not _tiling_satisfies_walls(t, walls):
            continue
        count += 1
    return count


# ---------------------------------------------------------------------------
# Wall hints: edges between cells that no single piece may cross
# ---------------------------------------------------------------------------
WALLS_PER_LEVEL = [10, 8, 6, 4, 2]  # hint edges per level (easier -> more)


def _tiling_owners(t):
    """Map every board cell to the piece covering it in tiling t."""
    owners = {}
    for pid, (cells, _) in t["placements"].items():
        for c in cells:
            owners[c] = pid
    return owners


def _tiling_satisfies_walls(t, walls):
    """True when every walled edge separates two different pieces in
    tiling t (no piece crosses a wall)."""
    owners = _tiling_owners(t)
    return all(owners[a] != owners[b] for a, b in walls)


def _level_walls(tiling, mice, count):
    """Pick up to `count` internal edges of `tiling` (where two different
    pieces meet) as wall hints, prioritising edges that touch a mouse cell:
    a rough outline around the mouse showing where the revealing piece
    cannot extend. Walls never occupy cells and never change the tiling;
    they only forbid placing a single piece across an edge."""
    owners = _tiling_owners(tiling)
    mice_set = set(mice)
    near = set()
    for m in mice_set:
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            near.add((m[0] + dx, m[1] + dy))

    def edge_rank(edge):
        a, b = edge
        mouse_touch = (a in mice_set) + (b in mice_set)
        near_touch = (a in near) + (b in near)
        return (-mouse_touch, -near_touch, a[1], a[0], b[1], b[0])

    cuts = []
    for y in range(BOARD_H):
        for x in range(BOARD_W):
            for dx, dy in ((1, 0), (0, 1)):
                a, b = (x, y), (x + dx, y + dy)
                if b in owners and owners[a] != owners[b]:
                    cuts.append((a, b))
    cuts.sort(key=edge_rank)
    return cuts[:count]


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


def _rotations_for_tiling(t):
    """Orientation index (0-3) each piece needs in a tiling, found by
    matching BOTH the placed cells and the opening cell (normalized)
    against rotated variants. Cells alone are ambiguous for pieces whose
    silhouette is 180-degree symmetric (plank, step, skew) -- their
    opening moves between the two orientations."""
    rotations = {}
    for pid, (cells, wopen) in t["placements"].items():
        minx = min(c[0] for c in cells)
        miny = min(c[1] for c in cells)
        norm_cells = tuple(sorted((c[0] - minx, c[1] - miny) for c in cells))
        norm_open = (wopen[0] - minx, wopen[1] - miny)
        for r in range(4):
            rc, ro = rotated_variant(PIECES[pid], r)
            if tuple(sorted(rc)) == norm_cells and ro == norm_open:
                rotations[pid] = r
                break
    return rotations


def _tiling_rot_count(t):
    """How many pieces in this tiling sit in a non-default orientation."""
    return sum(1 for r in _rotations_for_tiling(t).values() if r != 0)


def _min_rotations_required(tilings, mice, walls=None):
    """Fewest pieces a player must rotate across all satisfying tilings.
    0 means the level can be won without ever rotating a piece."""
    mice = set(mice)
    sats = [t for t in tilings if mice.issubset(t["openings"])]
    if walls:
        sats = [t for t in sats if _tiling_satisfies_walls(t, walls)]
    return min(_tiling_rot_count(t) for t in sats)


def _best_rotation_required_subset(tilings, k):
    """Pick the k-mice subset where EVERY satisfying tiling needs rotation
    (min_rot >= 1), preferring the most solutions so the level stays fair."""
    from itertools import combinations
    best = None
    for t in tilings:
        for mice in combinations(sorted(t["openings"]), k):
            sats = [u for u in tilings if set(mice).issubset(u["openings"])]
            if not sats:
                continue
            if min(_tiling_rot_count(u) for u in sats) < 1:
                continue  # can be won without rotating
            n = len(sats)
            if best is None or n > best[2] or (n == best[2]
                    and list(mice) < best[0]):
                best = (list(mice), t, n)
    return best


def _unique_rotation_required_tiling(tilings, used_mice_sets):
    """A tiling whose full opening set (6 mice) has a unique solution that
    requires rotation, differing the most from already-used mice sets."""
    best = None
    for t in tilings:
        if _tiling_rot_count(t) < 1:
            continue
        ops = frozenset(t["openings"])
        if ops in used_mice_sets:
            continue
        distance = min(len(ops - used) for used in used_mice_sets)
        if best is None or distance > best[1]:
            best = (t, distance)
    return best[0] if best else None





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
    #   -> level 3: 6 mice (unique solution, already requires rotation).
    # Levels 4-5 are rotation levels: NO winning tiling exists with every
    # piece in its default orientation, so the player must rotate to win.
    l1_mice, l1_tiling, l1_n = _best_mice_subset(tilings, 3)
    l2_mice, l2_tiling, l2_n = _best_mice_subset(tilings, 5)
    # Level 3 uses all 6 opening cells; pick a tiling whose mice positions
    # differ the most from level 2 to keep the levels visually distinct.
    l2_cells = set(l2_mice)
    l3_tiling = min(tilings, key=lambda t: len(t["openings"] & l2_cells))
    l3_mice = sorted(l3_tiling["openings"])
    l3_n = count_solutions_for_mice(tilings, l3_mice)
    # Level 4: 4-mice subset where every solution needs rotation, keeping
    # the solution count as high as possible so it stays fair.
    l4_mice, l4_tiling, l4_n = _best_rotation_required_subset(tilings, 4)
    # Level 5: all 6 openings of a rotation-requiring tiling (unique
    # solution), as visually distinct as possible from earlier levels.
    used = [set(l1_mice), set(l2_mice), set(l3_mice), set(l4_mice)]
    l5_tiling = _unique_rotation_required_tiling(tilings, used)
    l5_mice = sorted(l5_tiling["openings"])
    l5_n = count_solutions_for_mice(tilings, l5_mice)
    level_specs = [
        {"id": "kitchen_001", "room": "kitchen",
         "mice": l1_mice, "tiling": l1_tiling, "n": l1_n},
        {"id": "living_room_002", "room": "living_room",
         "mice": l2_mice, "tiling": l2_tiling, "n": l2_n},
        {"id": "bedroom_003", "room": "bedroom",
         "mice": l3_mice, "tiling": l3_tiling, "n": l3_n},
        {"id": "bathroom_004", "room": "bathroom",
         "mice": l4_mice, "tiling": l4_tiling, "n": l4_n},
        {"id": "attic_005", "room": "attic",
         "mice": l5_mice, "tiling": l5_tiling, "n": l5_n},
    ]
    ok = True
    for idx, spec in enumerate(level_specs):
        t = spec["tiling"]
        mice = list(spec["mice"])
        n = spec["n"]
        walls = _level_walls(t, mice, WALLS_PER_LEVEL[idx])
        n_walled = count_solutions_for_mice(tilings, mice, walls)
        min_rot = (_min_rotations_required(tilings, mice, walls)
                   if n_walled > 0 else -1)
        print(f"\nLevel {spec['id']} ({spec['room']}): mice={mice} "
              f"-> {n} satisfying solutions, "
              f"{n_walled} with walls, "
              f"minimum rotations required: {max(min_rot, 0)}")
        print(f"  walls ({len(walls)} edges): {walls}")
        tres_walls = ", ".join(
            "Vector2i(%d, %d), Vector2i(%d, %d)" % (a[0], a[1], b[0], b[1])
            for a, b in walls)
        print(f"  tres:   walls = Array[Vector2i]([{tres_walls}])")
        if n_walled == 0:
            print("  ERROR: level is not solvable with walls!")
            ok = False
        rotations = _rotations_for_tiling(t)
        out["levels"].append({
            "id": spec["id"], "room": spec["room"], "mice": mice,
            "placements": {pid: [list(c) for c in data[0]]
                           for pid, data in t["placements"].items()},
            "rotations": rotations,
            "min_rotations_required": max(min_rot, 0),
            "walls": [list(c) for pair in walls for c in pair],
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
