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
7. Win when every mouse is visible through an opening and every puzzle piece is placed legally.
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
- [x] Win detection: all pieces legally placed and all target mice revealed.
- [x] Reset level and restart controls.
- [x] At least three original, hand-authored test levels.
- [x] Simple success feedback and next-level navigation.
MVP Implementation Notes
- Board: 4 x 6 grid (24 cells) fully covered by six 4-cell pieces, each with one circular opening. The piece set (square, plank, corner, hook, step, skew) is checkerboard-balanced so a full tiling exists; the T shape is intentionally excluded because a single imbalanced piece can never tile an even-area rectangle.
- Pieces are Godot Resources (`data/pieces/*.tres`); levels reference them and define board size, room name and mice (`data/levels/level_001..005.tres`). New levels are discovered automatically by directory scan.
- Levels: Kitchen (3 mice, 16 solutions), Living Room (5 mice, 4 solutions), Bedroom (6 mice, unique), Bathroom (4 mice, 8 solutions), Attic (6 mice, unique). All verified solvable by `tests/level_solver.py`, which enumerates every legal tiling with the same rotation math as the game.
- Rotation levels: Bedroom, Bathroom and Attic cannot be won without rotating pieces (minimum 2-3 required rotations, solver-verified; the solver matches placed cells AND opening cells, since plank/step/skew silhouettes are 180-degree symmetric while their openings move).
- Gameplay logic is rendering-independent: `scripts/placement_validator.gd` does pure board-space cell math; `scripts/piece_definition.gd` owns rotation transforms. Piece textures (opaque cells + transparent punched holes) are generated procedurally from the same data.
- Input: one code path for mouse and touch (Godot's emulate_mouse_from_touch). Drag to move, tap (or R key) to rotate 90° clockwise, drop to snap; illegal drops and blocked rotations are rejected with a green/red snap preview. The HUD is authored directly in `scenes/main.tscn` for easy manual editing in the editor.
- Wall hints: `LevelDefinition.walls` is a flat list of adjacent cell pairs — the edge shared by each pair is walled, and no piece may cover both cells. `PlacementValidator.is_placement_legal` enforces walls for drops and rotations, and the board draws each wall as a short rough hand-drawn-looking stroke. `tests/level_solver.py` chooses walls from the reference tiling's internal boundaries (mouse-adjacent edges first), so hints never invalidate a solution; all five levels ship with walls (10/8/6/4/2 edges) without changing any solution count.
Later (Not MVP)
- Hint system and undo.
- Additional rooms and difficulty tiers.
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
- Controls: drag a piece with mouse or touch to move it; tap a piece (press + quick release without moving) or press R to rotate it 90° clockwise; drop on the board to snap. Illegal drops return the piece to the tray; placed pieces only rotate if the rotation stays legal. Pieces cannot be placed across the short wall outlines on cell edges. Win by covering the board completely with all openings revealing every mouse.
- Verify level solvability (also regenerates `tests/solutions.json`): `python3 tests/level_solver.py`
- Headless smoke test (loads the main scene, simulates drag/tap input, replays solver solutions, checks win/reset/next-level flow; cross-checks GDScript placement math against the Python solver): run the Godot binary with `--headless --path . --script res://tests/smoke_test.gd` — it prints PASS/FAIL lines and exits non-zero on failure.
Reference and Attribution
Gameplay inspiration: Ghost Hunters — SmartGames.

Mouse-Hunter is an independent project and is not affiliated with, sponsored by, or endorsed by SmartGames, Warner Bros., or the creators/owners of Tom & Jerry. Do not copy reference artwork, character likenesses, branding, challenge cards, or published level solutions into this repository without appropriate rights.
Project Status
MVP complete: all Minimum Viable Prototype requirements are implemented and validated headlessly (see Running and Testing). All five levels include solver-designed wall hints (short rough outlines on cell edges that no piece may cross) to ease the difficulty. Art is placeholder (procedural shapes); interactive feel on a real display still needs manual playtesting. Next up: milestone 5 (house theme and original art).