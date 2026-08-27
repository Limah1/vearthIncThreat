@tool
class_name GridPrototypeConfig
extends Resource

## Logical board settings for the isolated grid-combat prototype.
@export_range(2, 64, 1) var columns: int = 10
@export_range(2, 64, 1) var rows: int = 6
@export_range(20.0, 200.0, 1.0) var cell_size: float = 100.0
@export var world_origin: Vector2 = Vector2.ZERO
@export var blocked_cells: Array[Vector2i] = []

func is_cell_inside(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < columns and cell.y < rows

func is_cell_blocked(cell: Vector2i) -> bool:
	return blocked_cells.has(cell)
