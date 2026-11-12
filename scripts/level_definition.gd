class_name LevelDefinition
extends Resource
## Data definition of a puzzle level: board size, hidden mice and the
## piece set to arrange. Pure data -- no gameplay or scene dependencies.

@export var id: String = ""
@export var room: String = ""
@export var board_size: Vector2i = Vector2i(4, 6)
@export var mice: Array[Vector2i] = []
## Wall hints: flat list of adjacent cell pairs (a1, b1, a2, b2, ...). The
## edge shared by each pair is walled -- no single piece may cover both
## cells. Walls never occupy cells and never change the board area or the
## win condition; they only constrain placement, as a guideline for the
## player.
@export var walls: Array[Vector2i] = []
## Kept untyped on purpose: elements are PieceDefinition resources and an
## untyped Array serializes plainly in .tres files.
@export var pieces: Array = []


func get_room_title() -> String:
	return room.capitalize()
