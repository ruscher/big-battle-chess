class_name CinematicMode
extends RefCounted
## How captures are presented. The chess result never depends on this.

enum Mode { EPIC, DYNAMIC, QUICK, CLASSIC, SKIP }

const NAME_KEYS := ["CINE_EPIC", "CINE_DYNAMIC", "CINE_QUICK", "CINE_CLASSIC", "CINE_SKIP"]
const DESC_KEYS := ["CINE_EPIC_DESC", "CINE_DYNAMIC_DESC", "CINE_QUICK_DESC", "CINE_CLASSIC_DESC", "CINE_SKIP_DESC"]

## Target battle length range in seconds (arena modes only).
const DURATION := {
	Mode.EPIC: Vector2(30.0, 50.0),
	Mode.DYNAMIC: Vector2(10.0, 20.0),
	Mode.QUICK: Vector2(3.0, 6.0),
}


static func uses_arena(mode: int) -> bool:
	return mode == Mode.EPIC or mode == Mode.DYNAMIC or mode == Mode.QUICK
