extends RefCounted
## Save files for the career/league. A save is the whole season Dictionary (it contains the world, schedule,
## results, training state ...) plus a small header, written with FileAccess.store_var (binary: exact floats, ints and Colors).
## Autosave slot: user://league_auto.sav. Atomic write (temp file + rename) so a crash never leaves a broken save.
## Design: docs/design/经营与养成设计.md (stage 3), format notes in docs/架构说明.md.

const VERSION := 2      # 2: two-tier league, fixed world, story (M1/M2); version-1 saves are not loaded
const AUTO := "user://league_auto.sav"
const MAGIC := "NEONDRIFT-SAVE"

static func path(slot: String) -> String:
	return AUTO if slot == "auto" else "user://league_%s.sav" % slot

static func exists(slot := "auto") -> bool:
	return FileAccess.file_exists(path(slot))

## true on success
static func save_season(season: Dictionary, slot := "auto") -> bool:
	var p := path(slot)
	var tmp := p + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return false
	var head := {"magic": MAGIC, "version": VERSION, "saved_at": int(Time.get_unix_time_from_system()), "info": info_of(season)}
	f.store_var(head)
	f.store_var(season)
	f.close()
	var da := DirAccess.open("user://")
	if da == null:
		return false
	if da.file_exists(p.get_file()):
		da.remove(p.get_file())
	return da.rename(tmp.get_file(), p.get_file()) == OK

## the season Dictionary, or {} when missing / broken / from a newer version
static func load_season(slot := "auto") -> Dictionary:
	var p := path(slot)
	if not FileAccess.file_exists(p):
		return {}
	var f := FileAccess.open(p, FileAccess.READ)
	if f == null:
		return {}
	var head = f.get_var()
	if typeof(head) != TYPE_DICTIONARY or str(head.get("magic", "")) != MAGIC or int(head.get("version", 0)) > VERSION:
		return {}
	var body = f.get_var()
	if int(head.get("version", 0)) < 2:
		return {}
	if typeof(body) != TYPE_DICTIONARY or not body.has("world") or not body.has("leagues"):
		return {}
	return migrate(body, int(head.get("version", 1)))

## header only (cheap): {"team", "stage", "week", "saved_at"} or {}
static func peek(slot := "auto") -> Dictionary:
	var p := path(slot)
	if not FileAccess.file_exists(p):
		return {}
	var f := FileAccess.open(p, FileAccess.READ)
	if f == null:
		return {}
	var head = f.get_var()
	if typeof(head) != TYPE_DICTIONARY or str(head.get("magic", "")) != MAGIC:
		return {}
	var out: Dictionary = head.get("info", {})
	out["saved_at"] = int(head.get("saved_at", 0))
	return out

static func delete(slot := "auto") -> void:
	if exists(slot):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path(slot)))

static func info_of(season: Dictionary) -> Dictionary:
	var team := ""
	for t in season["world"]["teams"]:
		if str(t["id"]) == str(season.get("human", "")):
			team = str(t["name"])
	return {"team": team, "phase": str(season["phase"]), "week": int(season["week"]), "season_no": int(season.get("no", 1)),
		"weeks": (season["leagues"]["pro"]["weeks"] as Array).size(), "champion": str(season.get("champion", "")), "seed": int(season["seed"])}

## bring an old save up to the current format (no changes needed yet; training fields are added lazily by Training.ensure)
static func migrate(season: Dictionary, _from: int) -> Dictionary:
	return season
