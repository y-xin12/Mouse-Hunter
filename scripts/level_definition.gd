class_name LevelDefinition
extends Resource
## Data definition of a puzzle level: board size, hidden mice and the
## piece set to arrange. Pure data -- no gameplay or scene dependencies.

@export var id: String = ""
@export var room: String = ""
@export var board_size: Vector2i = Vector2i(4, 6)
@export var mice: Array[Vector2i] = []
## Kept untyped on purpose: elements are PieceDefinition resources and an
## untyped Array serializes plainly in .tres files.
@export var pieces: Array = []


func get_room_title() -> String:
	return room.capitalize()
