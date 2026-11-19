#!/usr/bin/env python3
"""Generate easy/hard wall variants for every Mouse-Hunter level.

The base `walls` list in each data/levels/level_XXX.tres is the "medium"
variant. This script derives two more variants per level and inserts them
as a single `wall_variants = {...}` line right after the `walls` line:

  easy  = base walls + extra hint walls (more guidance), taken from edges
          the reference solution crosses between two DIFFERENT pieces, so
          the shipped solution can never be invalidated. Extras touching a
          mouse cell come first (the solver's hint convention), then plain
          coordinate order, so generation is fully deterministic.
  hard  = the first half of the base walls (fewer hints).

Sizing: easy adds max(2, ceil(base/2)) walls capped by the safe pool,
hard keeps floor(base/2). The base list itself is never modified.

Run:  python3 tests/variant_generator.py
Idempotent: levels that already carry `wall_variants` are skipped.
"""
import json
import math
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
LEVELS_DIR = ROOT / "data" / "levels"
SOLUTIONS = ROOT / "tests" / "solutions.json"

VEC_RE = re.compile(r"Vector2i\((-?\d+),\s*(-?\d+)\)")


def parse_vec2i(text):
    return [(int(m.group(1)), int(m.group(2))) for m in VEC_RE.finditer(text)]


def fmt_vec2i_array(flat):
    inner = ", ".join("Vector2i(%d, %d)" % (x, y) for (x, y) in flat)
    return "Array[Vector2i]([%s])" % inner


def pairs_of(flat):
    return [(flat[i], flat[i + 1]) for i in range(0, len(flat), 2)]


def flatten(pairs):
    return [c for pair in pairs for c in pair]


def norm(pair):
    a, b = pair
    return (a, b) if a <= b else (b, a)


def solution_owners(entry):
    """Map board cell -> owning piece index for the reference solution."""
    owner = {}
    for idx, cells in enumerate(entry["placements"].values()):
        for cx, cy in cells:
            owner[(cx, cy)] = idx
    return owner


def safe_edge_pool(entry, base_norm):
    """All inter-piece adjacency edges not already walled, deterministically
    ordered: mouse-adjacent edges first, then by coordinates."""
    owner = solution_owners(entry)
    mice = {(mx, my) for mx, my in entry["mice"]}
    pool = set()
    for (x, y), idx in owner.items():
        for dx, dy in ((1, 0), (0, 1)):  # right/down only: canonical edges
            other = (x + dx, y + dy)
            if other in owner and owner[other] != idx:
                edge = ((x, y), other)
                if edge not in base_norm:
                    pool.add(edge)
    return sorted(pool, key=lambda e: (
        0 if (e[0] in mice or e[1] in mice) else 1,
        e[0][0], e[0][1], e[1][0], e[1][1]))


def assert_solution_legal(entry, variant_pairs, label):
    """No variant wall may sit inside one piece of the reference solution
    (walls only forbid a single piece covering both of their cells)."""
    owner = solution_owners(entry)
    for a, b in variant_pairs:
        assert owner[a] != owner[b], (
            "%s wall %s-%s lies inside one piece" % (label, a, b))


def build_variants(entry):
    """Return (base_count, easy_pairs, hard_pairs, pool_size)."""
    base_pairs = pairs_of(parse_vec2i(entry["walls_flat"]))
    base_norm = {norm(p) for p in base_pairs}
    pool = safe_edge_pool(entry, base_norm)
    n_base = len(base_pairs)
    n_extra = min(len(pool), max(2, math.ceil(n_base / 2)))
    easy_pairs = [norm(p) for p in base_pairs] + pool[:n_extra]
    hard_pairs = [norm(p) for p in base_pairs[: n_base // 2]]
    # easy must be a superset of base, hard a subset, both solution-legal.
    assert set(norm(p) for p in easy_pairs[:n_base]) == base_norm
    assert set(hard_pairs) <= base_norm
    assert_solution_legal(entry, easy_pairs, "easy")
    assert_solution_legal(entry, hard_pairs, "hard")
    return n_base, easy_pairs, hard_pairs, len(pool)


def main():
    data = json.loads(SOLUTIONS.read_text())
    levels = data["levels"]
    print("%-6s %-18s %5s %5s %5s %5s"
          % ("level", "id", "base", "easy", "hard", "pool"))
    changed = 0
    for i, entry in enumerate(levels):
        level_no = i + 1
        tres = LEVELS_DIR / ("level_%03d.tres" % level_no)
        text = tres.read_text()
        if "wall_variants" in text:
            print("%-6d %-18s   (already has wall_variants, skipped)"
                  % (level_no, entry["id"]))
            continue
        # The level file's own walls are the source of truth (the smoke
        # test already asserts they match solutions.json's "walls").
        m = re.search(r"\[resource\]\n(?:.*\n)*?^walls = (.*)$", text, re.M)
        assert m, "%s: no walls line in [resource] section" % tres
        tres_flat = parse_vec2i(m.group(1))
        json_flat = [tuple(c) for c in entry["walls"]]
        assert [list(c) for c in tres_flat] == [list(c) for c in json_flat], (
            "%s: tres walls differ from solutions.json" % tres)
        entry = dict(entry)
        entry["walls_flat"] = m.group(1)
        n_base, easy_pairs, hard_pairs, pool_size = build_variants(entry)
        variant_line = 'wall_variants = {"easy": %s, "hard": %s}' % (
            fmt_vec2i_array(flatten(easy_pairs)),
            fmt_vec2i_array(flatten(hard_pairs)))
        lines = text.splitlines(keepends=True)
        for li, line in enumerate(lines):
            if line.startswith("walls = ") and "[resource]" in "".join(lines[:li]):
                lines.insert(li + 1, variant_line + "\n")
                break
        else:
            raise AssertionError("%s: walls line not found for insertion" % tres)
        tres.write_text("".join(lines))
        changed += 1
        print("%-6d %-18s %5d %5d %5d %5d"
              % (level_no, entry["id"], n_base, len(easy_pairs),
                 len(hard_pairs), pool_size))
    print("updated %d level file(s)" % changed)


if __name__ == "__main__":
    sys.exit(main())
