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
6. Win when every mouse is visible through an opening and every puzzle piece is placed legally.
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
- [ ] Main puzzle board with configurable dimensions.
- [ ] Six distinct puzzle pieces defined by data, not hard-coded positions.
- [ ] Visible mouse markers placed at level-defined coordinates.
- [ ] Opaque tile areas and circular transparent openings.
- [ ] Drag-and-drop controls for mouse and touch.
- [ ] Piece rotation and grid snapping.
- [ ] Legal-placement checks: inside board, no overlap, and correct coverage.
- [ ] Win detection: all pieces legally placed and all target mice revealed.
- [ ] Reset level and restart controls.
- [ ] At least three original, hand-authored test levels.
- [ ] Simple success feedback and next-level navigation.
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
- Optional locked pieces or obstacles, if introduced later.
Placement validation must ensure each placed piece is within bounds, no occupied cells overlap, and the complete board is covered when the level requires full tiling.

Reveal validation should calculate the transformed positions of the piece openings after rotation and placement, then check whether every target mouse is inside a visible opening. Use deterministic board-space geometry rather than visual sprite overlap alone.

Level completion occurs only when all required pieces are placed legally and every mouse is revealed. The level solver should eventually verify that each authored challenge has at least one valid solution, preferably exactly one if that becomes a design requirement.
Example level schema (illustrative only)
{
  "id": "kitchen_001",
  "room": "kitchen",
  "board_size": [4, 4],
  "mice": [[0, 1], [2, 3]],
  "piece_set": "starter_set",
  "allowed_rotations": [0, 90, 180, 270]
}
The example is not a guaranteed solvable level. Piece geometry and actual board dimensions will be established during implementation.
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
1. Foundation: Godot project, board, placeholder pieces, basic layout.
2. Interaction: Drag, touch, rotate, snap, and placement feedback.
3. Puzzle Logic: Legal-placement validation, mouse reveal detection, win condition.
4. Playable Content: Three verified levels, reset, next-level flow.
5. House Theme: Original mouse art, kitchen backdrop, UI styling, simple effects.
6. Expansion: Additional rooms, hints, progression, and puzzle generator.
Reference and Attribution
Gameplay inspiration: Ghost Hunters — SmartGames.

Mouse-Hunter is an independent project and is not affiliated with, sponsored by, or endorsed by SmartGames, Warner Bros., or the creators/owners of Tom & Jerry. Do not copy reference artwork, character likenesses, branding, challenge cards, or published level solutions into this repository without appropriate rights.
Project Status
Planning / pre-production. The README defines the intended implementation; no gameplay functionality is claimed to be complete.