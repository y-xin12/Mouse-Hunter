# Mouse-Hunter

A single-player spatial logic puzzle game built with Godot 4.x and GDScript, inspired by the tabletop puzzle mechanics of SmartGames Ghost Hunters.
Concept
The game takes place inside a playful, cartoon-style house inspired by classic cat-and-mouse comedy. Mischievous mice hide around the rooms, and the player must arrange puzzle tiles to reveal every mouse through designated circular openings.

The atmosphere evokes the slapstick energy of classic cartoons, while using original characters, art, names, sounds, and level designs rather than official Tom & Jerry assets.
Core Gameplay
1. Select a puzzle level set in a room of the house.
2. View the fixed positions of the hidden mice on the board.
3. Drag and rotate the available puzzle pieces onto the board.
4. Each piece has opaque areas and one or more transparent circular openings.
5. Arrange all pieces to cover the puzzle board without overlap or gaps, according to the level's tile layout.
6. Wall hints: short rough outlines on some edges between cells. No piece may be placed across a wall; the cells on both sides stay coverable. Walls never occupy cells or change the board area — they mark spots where pieces are cut in every valid solution, guiding players who are struggling.
7. Win when every mouse is visible through an opening and every puzzle piece is placed legally. A completion popup then rates the level with 1–3 stars and reports the moves used and the elapsed time; it offers Next Level while a next numbered level exists, and Home at the end of the catalog.
Reference mechanics: Ghost Hunters uses six transparent pieces and challenges where ghosts must be visible in circular light beams. Mouse-Hunter adapts that spatial-placement idea to mice and a household setting. The exact board dimensions, piece silhouettes, rotation rules, and opening positions must be defined and validated during prototyping; they should not be assumed from the reference.
Theme and Setting
Setting: A cozy, exaggerated cartoon house with oversized furniture, wooden floors, skirting boards, mouse holes, crumbs, and playful signs of a cat-and-mouse chase.

Room themes (future levels):
- Kitchen — cheese crumbs, cupboards, plates, and pantry shelves.
- Living room — sofa, carpet, fireplace, and scattered toys.
- Bedroom — slippers, bedposts, drawers, and blankets.
- Attic — boxes, old clocks, dusty beams, and trunks.
- Basement — pipes, storage crates, and hidden mouse tunnels.
Visual direction: Warm colors, bold silhouettes, readable puzzle pieces, subtle shadows, expressive original mouse characters, and a playful 2D cartoon aesthetic. Keep decoration outside the puzzle grid or behind it so it never obscures gameplay.

Tone: Lighthearted and mischievous, not violent. The goal is to spot the mice, not harm them.
Target Platform and Tech Stack
Area	Choice
Engine	Godot 4.x
Language	GDScript
Game type	Single-player, turn-free logic puzzle
Rendering	2D
Input	Mouse and touch
Primary target	Mobile (portrait)
Secondary target	Desktop
Assets	Placeholder shapes initially; original artwork later
Level data	Godot Resources or JSON


Use responsive layouts and consistent coordinate conversion between screen space and board space. Dragging must work with both mouse and touchscreen input.
Minimum Viable Prototype (MVP)
Required
- [x] Main puzzle board with configurable dimensions.
- [x] Six distinct puzzle pieces defined by data, not hard-coded positions.
- [x] Visible mouse markers placed at level-defined coordinates.
- [x] Opaque tile areas and circular transparent openings.
- [x] Drag-and-drop controls for mouse and touch.
- [x] Piece rotation and grid snapping.
- [x] Legal-placement checks: inside board, no overlap, and correct coverage.
- [x] Win detection: all pieces legally placed and all target mice revealed, with a star-rated completion popup (moves, time, next or home).
- [x] Reset level and restart controls.
- [x] At least three original, hand-authored test levels.
- [x] Simple success feedback and next-level navigation.
MVP Implementation Notes
- Board: 4 x 6 grid (24 cells) fully covered by six 4-cell pieces, each with one circular opening. The piece set (square, plank, corner, hook, step, skew) is checkerboard-balanced so a full tiling exists; the T shape is intentionally excluded because a single imbalanced piece can never tile an even-area rectangle.
- Pieces are Godot Resources (`data/pieces/*.tres`); levels reference them and define board size, room name and mice (`data/levels/level_001..005.tres`). New levels are discovered automatically by directory scan.
- Levels: one continuous numbered catalog of 25 stages (no player-facing difficulty split). Five of them are the original solver-designed levels — Kitchen (L1, 3 mice, 16 solutions), Living Room (L7, 5 mice, 4 solutions), Bedroom (L13, 6 mice, unique), Bathroom (L14, 4 mice, 8 solutions), Attic (L20, 6 mice, unique) — all verified solvable by `tests/level_solver.py`, which enumerates every legal tiling with the same rotation math as the game. The other twenty come from the level generator (4×5 boards for the smaller stages, 6×6 and 8×8 for the later, harder ones) with per-level custom piece shapes (3–10 cells) embedded as `PieceDefinition` sub-resources in their .tres files; their shipped solutions are stored in `tests/solutions.json` (in level order) and replayed in-game by the smoke test.
- Rotation levels: Bedroom, Bathroom and Attic cannot be won without rotating pieces (minimum 2-3 required rotations, solver-verified; the solver matches placed cells AND opening cells, since plank/step/skew silhouettes are 180-degree symmetric while their openings move).
- Gameplay logic is rendering-independent: `scripts/placement_validator.gd` does pure board-space cell math; `scripts/piece_definition.gd` owns rotation transforms. Piece textures (opaque cells + transparent punched holes) are generated procedurally from the same data.
- Input: one code path for mouse and touch (Godot's emulate_mouse_from_touch). Drag to move, tap (or R key) to rotate 90° clockwise, drop to snap; illegal drops and blocked rotations are rejected with a green/red snap preview. The HUD is authored directly in `scenes/main.tscn` for easy manual editing in the editor.
- Wall hints: `LevelDefinition.walls` is a flat list of adjacent cell pairs — the edge shared by each pair is walled, and no piece may cover both cells. `PlacementValidator.is_placement_legal` enforces walls for drops and rotations, and the board draws each wall as a short rough hand-drawn-looking stroke. `tests/level_solver.py` chooses walls from the reference tiling's internal boundaries (mouse-adjacent edges first), so hints never invalidate a solution; all twenty-five levels ship with walls (the original five carry 10/8/6/4/2 edges without changing any solution count). Every level additionally carries `wall_variants` — an "easy" set (base walls plus extra safe hints) and a "hard" set (roughly half the base walls) generated by `tests/variant_generator.py` from the reference solutions, so every variant keeps the shipped solution legal; the base list is the "medium" variant.
- Render order: board and tray (layer 0) → HUD (layer 1) → pieces (`PiecesLayer`, layer 2) → level-complete popup (`WinLayer`, layer 3) → home menu (`MenuLayer`, layer 4). Pieces therefore draw above the top bar/goal label, the completion popup stays above them, and the menu covers everything.
- Home screen: the MOUSE HUNTER logo art, the peeking mouse resting its paws on the single glossy Play button, and the button's dark level pill showing the 1-based numbered level it will continue at — one unified progression (no difficulty selection). Winning level N unlocks N+1 (`GameManager.highest_unlocked_level`); the pill clamps to the catalog size and always replays the last level once the catalog is finished. Each numbered level also has an internal challenge category from `LevelDefinition.get_level_category()`: levels ending in 7 are "hard" milestones, levels ending in 2 beyond Level 2 are "super_hard" milestones, everything else is "normal" — this classification is invisible to the player (debug tooling may surface it). Progression persists across sessions in `user://savegame.json` (`scripts/save_data.gd`, atomic temp-file writes, tolerant of missing/extra fields): the highest unlocked level, the current level, the completed-level list, and the adaptive-skill state below. Gameplay input is ignored while the menu is open. The menu is authored in a 720×1280 design space and fitted to the real canvas in `GameManager._layout_home()` (uniform scale on both axes, centered) so the button stays reachable at any window size. The UI art — kitchen-room background, logo, peeking mouse, the glossy button (`assets/UI/level_button/`) and its level pill (`assets/UI/level_pill/`) — was sliced from a source sprite sheet (the one-off slicer script has since been removed; the slices are committed); home and popup text use Fredoka Bold (`assets/Font/`), and all menu/popup buttons share the shrink-and-darken press animation in `scripts/juicy_button.gd`.
- Adaptive difficulty ("user_level_v1"): `scripts/skill_tracker.gd` keeps an internal skill tier (lv1–lv5, new players start at lv2) that is never shown to the player. Every completed level records one result — clean (no restart/prop/failure/quit) or problematic — but tiers are only evaluated from the Level-5 boundary on, at most one step per level, and replays of already completed levels never count. Upgrades need a tier-specific run of consecutive clean clears (2/2/3/5 for lv1–lv4); downgrades fire when the share of problematic results in the tier's rolling window (2/2/3/5/5) is strictly over half; the streak and window reset on every change. The tier maps to a wall variant (`skill_to_variant`: lv1/2 easy, lv3 medium, lv4/5 hard); the variant content ships in every level resource (`wall_variants`, see Wall hints). Levels 1–4 always play the base "medium" configuration; from Level 5 on, `GameManager._assign_variant()` picks the current tier's variant the first time a level loads and pins it in the save (`assigned_variants`) — a pinned level keeps its variant forever, even after the skill tier changes.
- Debug overlay: in debug builds only (`OS.is_debug_build()`), F1 or the small semi-transparent "DBG" circle docked on the right edge toggles a readout of the adaptive state (`scripts/debug_overlay.gd`): skill tier, clean streak vs. the upgrade requirement, the rolling downgrade window, the current level's internal category and pinned wall variant, the save path, and the recent skill changes with their reasons. It is the only place the internal skill rating is surfaced; release exports never create it. The panel also provides dev controls: simulate a clean clear (auto-solve via the solver-verified `tests/solutions.json`, through the real win path), a restarted clear, or an abandoned attempt (marks the attempt restarted and returns home, recording no skill result — mirroring the real quit flow); override the skill tier (resets streak/window like a real change, logged as a "debug override"; pinned level variants stay); preview any wall variant visually or apply one to the loaded level for the session (the save's pinned variant is never rewritten); jump straight to any catalog level (the real load path, so variants pin as usual but progression is never granted); and wipe the save back to the fresh-player state with a two-press reset.
- Level-complete popup: `WinPopup` in `scenes/main.tscn` (script `scripts/level_complete_popup.gd`) fills the screen with the same kitchen background as the home screen, dims it, and pops in a card composed from the UI art: the peeking mouse over the wooden completion board, the LEVEL COMPLETE banner, the star-rating image matching the result (`assets/UI/3 Stars.png`, `2 Stars.png` or `1 star.png`), and the `moves and time.png` stats bar. The mouse is layered for the peeking illusion: the full sprite sits behind the board so the board covers its lower face, while two `AtlasTexture` regions cropped to just the paws (`PawLeft`/`PawRight`) draw in front of the board, so the paws grip the board's top edge. The stats bar art carries the baked-in Moves/Time captions and icons; the live values — the legal drops completed this level (`GameManager.move_count`; rejected drops and tap-rotations do not count) and the elapsed time as MM:SS — are centered beneath their captions. Stars come from `GameManager._star_count()`: three for one drop per piece, two with up to three extra drops, one otherwise. The `next level.png` button is offered while a next numbered level exists in the catalog; on the last level it is replaced by the `home.png` button returning to the title screen (`GameManager._has_next_level()`). The card is authored at 631×962 px and uniformly scaled to fit both canvas axes (the same fitting rule as the home menu), so the composition never clips at any window size; the entrance animation is a dimmer fade, a back-ease card pop, and a delayed star pop. The `replay.png` button sits below the main action in both variants. All three art buttons are `TextureButton`s sharing the `juicy_button.gd` press animation (logo bob disabled).
Later (Not MVP)
- Hint system and undo.
- More numbered levels and richer in-level variety.
- Animated mouse reactions and household effects.
- Sound effects, music, and transitions.
- Progress saving and level selection.
- Automated level generation and uniqueness verification.
- Accessibility options and localization.
Puzzle Rules and Data Model
A level should describe:
- Board width and height in logical grid cells.
- Mouse target coordinates.
- Piece IDs and their occupied cell footprints.
- Circular opening positions relative to each piece.
- Allowed orientations for each piece.
- Wall hints: flat pairs of adjacent cells whose shared edge no piece may cross.
- Optional locked pieces or obstacles, if introduced later.
Placement validation must ensure each placed piece is within bounds, no occupied cells overlap, no walled edge is crossed by one piece, and the complete board is covered when the level requires full tiling.

Reveal validation should calculate the transformed positions of the piece openings after rotation and placement, then check whether every target mouse is inside a visible opening. Use deterministic board-space geometry rather than visual sprite overlap alone.

Level completion occurs only when all required pieces are placed legally and every mouse is revealed. The level solver should eventually verify that each authored challenge has at least one valid solution, preferably exactly one if that becomes a design requirement.
Example level schema (illustrative only)
{
  "id": "kitchen_001",
  "room": "kitchen",
  "board_size": [4, 4],
  "mice": [[0, 1], [2, 3]],
  "walls": [[0, 1], [1, 1]],
  "piece_set": "starter_set",
  "allowed_rotations": [0, 90, 180, 270]
}
The example is not a guaranteed solvable level. Piece geometry and actual board dimensions will be established during implementation. `walls` is a flat list of adjacent cell pairs; the edge shared by each pair is a wall no single piece may cross.
Proposed Project Structure
mouse-hunter/
├── README.md
├── AGENTS.md
├── project.godot
├── scenes/
│   ├── main.tscn
│   ├── puzzle_board.tscn
│   ├── puzzle_piece.tscn
│   └── ui/
├── scripts/
│   ├── game_manager.gd
│   ├── board_controller.gd
│   ├── puzzle_piece.gd
│   ├── placement_validator.gd
│   └── level_loader.gd
├── data/
│   ├── levels/
│   └── pieces/
├── assets/
│   ├── art/
│   ├── audio/
│   └── fonts/
└── tests/
This is a proposed structure, not a claim that these files already exist.
Development Guidelines
- Prioritize correct puzzle behavior before polishing art or effects.
- Keep puzzle state and validation independent of rendering and animation.
- Store levels and piece shapes in reusable data structures.
- Avoid duplicating drag, rotation, snapping, and validation logic.
- Support touch interaction from the first playable version.
- Keep the project runnable after each incremental feature.
- Test mouse/touch input, edge placements, rotations, overlapping pieces, reset behavior, and win detection.
- Do not introduce unrelated mechanics or large dependencies without approval.
- Ask for approval before modifying AGENTS.md or changing the project's established development rules.
- Update this README when setup, architecture, core mechanics, or project scope changes.
Development Milestones
1. Foundation: Godot project, board, placeholder pieces, basic layout. (done)
2. Interaction: Drag, touch, rotate, snap, and placement feedback. (done)
3. Puzzle Logic: Legal-placement validation, mouse reveal detection, win condition. (done)
4. Playable Content: Three verified levels, reset, next-level flow. (done)
5. House Theme: Original mouse art, kitchen backdrop, UI styling, simple effects.
6. Expansion: Additional rooms, hints, progression, and puzzle generator.
Running and Testing
- Open the project in Godot 4.x and press Play (main scene: `scenes/main.tscn`), or run the editor binary directly with the project path.
- Controls: drag a piece with mouse or touch to move it; tap a piece (press + quick release without moving) or press R to rotate it 90° clockwise; drop on the board to snap. Swipe the tray sideways to scroll its piece carousel: three pieces are visible at a time, all rendered at the same size regardless of rotation, and a touch stops the glide at any point. Illegal drops return the piece to the tray; placed pieces only rotate if the rotation stays legal. Pieces cannot be placed across the short wall outlines on cell edges. Win by covering the board completely with all openings revealing every mouse.
- Verify level solvability of the five original levels (also regenerates `tests/solutions.json` — warning: the solver only covers those five, so re-running it rewrites the file and drops the twenty generator levels' replay entries): `python3 tests/level_solver.py`
- Regenerate the easy/hard wall variants in every level .tres from the reference solutions (idempotent; skips levels that already carry `wall_variants`, so delete the line first to force a rebuild): `python3 tests/variant_generator.py`
- Headless smoke test (loads the main scene, simulates drag/tap input, replays solver solutions, checks move counting, the completion popup results, the level-category classification, all 25 levels' easy/hard wall variants plus an end-to-end win under the easy variant, the unified Play/Next/Home progression, the adaptive-skill walk and the persisted save file; cross-checks GDScript placement math against the Python solver): run the Godot binary with `--headless --path . --script res://tests/smoke_test.gd` — it prints PASS/FAIL lines and exits non-zero on failure.
- Headless skill/save unit tests (SkillTracker upgrade thresholds, downgrade windows, evaluation gating, streak/window resets, skill→variant mapping; SaveData roundtrip, corrupt/legacy file handling): `--headless --path . --script res://tests/skill_test.gd`.
- Responsive layout check (applies the project's `canvas_items` + `expand` stretch settings and runs the main scene at 720x1280, 1080x2400 and 1440x2960 window sizes; verifies uniform device scaling, square board cells, board centering with no HUD/tray overlap, drag/tap input alignment at every size, plus a live window resize): run the Godot binary with `--headless --path . --script res://tests/resolution_check.gd`.
Reference and Attribution
Gameplay inspiration: Ghost Hunters — SmartGames.

Mouse-Hunter is an independent project and is not affiliated with, sponsored by, or endorsed by SmartGames, Warner Bros., or the creators/owners of Tom & Jerry. Do not copy reference artwork, character likenesses, branding, challenge cards, or published level solutions into this repository without appropriate rights.
Project Status
MVP complete: all Minimum Viable Prototype requirements are implemented and validated headlessly (see Running and Testing). All twenty-five levels include solver-designed wall hints (short rough outlines on cell edges that no piece may cross) to ease the difficulty. The home screen shows sliced sprite-sheet art over a full-screen kitchen background (`assets/UI/`) and Fredoka Bold, as does the enlarged completion popup; in-game pieces remain procedural placeholders. Interactive feel on a real display still needs manual playtesting. Next up: milestone 5 (house theme and original art).