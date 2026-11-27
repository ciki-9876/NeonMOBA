extends Node
## Shop / inventory UI (shop rules live in game/match.gd).
## (split out of the old monolithic main.gd — see docs/架构说明.md)

const C = preload("res://game/consts.gd")
const Unit = preload("res://unit.gd")
const Hero = preload("res://hero.gd")
const HeroAI = preload("res://hero_ai.gd")
const TeamAI = preload("res://team_ai.gd")
const HeroesDB = preload("res://heroes_db.gd")
const ItemsDB = preload("res://items_db.gd")
const Grid = preload("res://view/grid.gd")
const Ring = preload("res://view/ring.gd")

const MatchT = preload("res://game/match.gd")
var gm: MatchT

const PresenterT = preload("res://view/presenter.gd")
var vw: PresenterT
const HudT = preload("res://ui/hud.gd")
var hd: HudT
const MenusT = preload("res://ui/menus.gd")
var mnu: MenusT
const PlayerInputT = preload("res://input/player_input.gd")
var inp: PlayerInputT
## main.gd (composition root)
var app: Node = null

var shop_open := false
var shop_tab := "basic"
var shop_hover := ""
var shop: PanelContainer
var shop_grid: GridContainer
var shop_detail: RichTextLabel
var shop_gold: Label
var shop_tabs := {}
var gold_lbl: Label
var inv_slots: Array = []
func _buy(id: String) -> void:
	if gm.state != C.S.PLAY or gm.player == null: return
	var err := gm.buy_for(gm.player, id, true)
	if err != "":
		inp._deny(err)
	_refresh_inv()
	_refresh_shop()

func _sell(i: int) -> void:
	if gm.state != C.S.PLAY or gm.player == null or i >= gm.player.inv.size(): return
	var id: String = gm.player.inv[i]
	if gm.rounds != null and gm.rounds.shop_block_reason() != "":
		hd.toast(gm.rounds.shop_block_reason(), Color(1.0, 0.5, 0.4), 2.0)
		return
	var v := gm.sell_for(gm.player, i)
	vw.sfx("select", 0.8, -6.0)
	hd.toast("出售 %s（+%d 金）" % [ItemsDB.DB[id]["name"], int(v)], Color(1.0, 0.85, 0.3), 2.5)
	_refresh_inv()
	_refresh_shop()

func _on_inv_input(ev: InputEvent, i: int) -> void:
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_RIGHT:
		_sell(i)

func _on_shop_input(ev: InputEvent, id: String) -> void:
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_RIGHT:
		_buy(id)

const Tune = preload("res://game/tuning.gd")
const STAT_NAMES := {"atk": "攻击力（全局倍率后）", "as": "% 基础攻速（全局倍率后）", "def": "物理防御", "res": "法术防御", "ms": "移动速度",
	"hp": "生命值", "mana": "法力值", "hpr": "生命回复", "mpr": "法力回复", "ls": "% 吸血", "pow": "% 技能强度",
	"cdr": "% 冷却缩减", "range": "攻击距离", "pspd": "弹道速度", "vision": "视野"}
const CAT_NAMES := {"basic": "基础", "advanced": "进阶", "ultimate": "终极", "upgrade": "英雄强化"}
func _num(v: float) -> String:
	return str(int(v)) if absf(v - roundf(v)) < 0.01 else ("%.2f" % v).rstrip("0")

func _item_text(id: String, with_price: bool) -> String:
	var it: Dictionary = ItemsDB.DB[id]
	var cat_name: String = CAT_NAMES.get(it["cat"], "")
	var out := "[b][color=#ffd23f]%s[/color][/b]  [color=#8a92b8]%s[/color]   [color=#ffcc44]%d 金[/color]\n" % [it["name"], cat_name, int(it["cost"])]
	var stv: Dictionary = it["stats"]
	var parts := []
	for k in stv:
		var nm: String = STAT_NAMES.get(k, k)
		var amount := float(stv[k])
		if k == "atk": amount *= Tune.ATTACK_DAMAGE_MULT
		elif k == "as": amount *= Tune.ATTACK_SPEED_MULT
		if k == "range" and gm.player != null and bool(gm.player.def["melee"]):
			nm += "（近战减半）"
		parts.append(("+%s%s" if nm.begins_with("%") else "+%s %s") % [_num(amount), nm])
	if not parts.is_empty():
		out += "[color=#c8f0ff]" + "   ".join(PackedStringArray(parts)) + "[/color]\n"
	var spc: Dictionary = it["special"]
	var note: String = it["note"]
	for k in spc:
		var v = spc[k]
		match k:
			"scepter": out += "[color=#6ab0ff]%s[/color]\n" % (str(gm.player.def.get("scepter_note", "")) if gm.player != null else "")
			"crit", "arc", "pierce", "armor_break", "grievous", "charge_fast", "tenacity", "spell_shield", "regen_ooc", "charge_move", "hurt_haste", "far_bonus", "heal_amp", "as_aura", "heart", "low_ls", "spell_vamp":
				pass   # described by the item note (tools/gen_items.py)
			"shard":
				if gm.player != null: note = str(gm.player.def.get("shard_note", note))
	if note != "":
		out += "[color=#a0ffa0]被动：%s[/color]\n" % note if not spc.has("shard") else "[color=#a0ffa0]%s[/color]\n" % note
	var comps: Array = it["comps"]
	if not comps.is_empty() and gm.player != null:
		var avail: Array = gm.player.inv.duplicate()
		var cn := []
		for c in comps:
			var j := avail.find(c)
			var nm2: String = ItemsDB.DB[c]["name"]
			if j >= 0:
				avail.remove_at(j)
				cn.append("[color=#6aff8a]%s ✓[/color]" % nm2)
			else:
				cn.append("%s(%d)" % [nm2, int(ItemsDB.DB[c]["cost"])])
		if int(it["recipe"]) > 0:
			cn.append("升级(%d)" % int(it["recipe"]))
		out += "[color=#b0b0c8]合成：[/color]" + " + ".join(PackedStringArray(cn)) + "\n"
		if with_price:
			var need := gm.shop_price_for(gm.player, id)
			if need < int(it["cost"]):
				out += "[color=#ffcc44]已有部分配件，还需 %d 金[/color]\n" % need
	return out

func _strip_bb(text: String) -> String:
	var re := RegEx.new()
	re.compile("\\[[^\\]]*\\]")
	return re.sub(text, "", true)

func _rt(size: int) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.scroll_active = false
	r.add_theme_font_override("normal_font", vw.ui_font)
	r.add_theme_font_override("bold_font", vw.ui_font)
	r.add_theme_font_size_override("normal_font_size", size)
	r.add_theme_font_size_override("bold_font_size", size + 1)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r

func _small_btn(text: String, w: float) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(w, 28)
	b.add_theme_font_override("font", vw.ui_font)
	b.add_theme_font_size_override("font_size", 16)
	b.add_theme_stylebox_override("normal", hd._panel_style(Color(0.1, 0.08, 0.18, 0.95), Color(0.3, 0.8, 1.0, 0.6)))
	b.add_theme_stylebox_override("hover", hd._panel_style(Color(0.18, 0.12, 0.3, 0.95), Color(1.0, 0.85, 0.3)))
	b.add_theme_stylebox_override("pressed", hd._panel_style(Color(0.25, 0.18, 0.05, 0.95), Color(1.0, 0.85, 0.3)))
	return b

func _build_ui_v3() -> void:
	var ap := PanelContainer.new()
	hd._place(ap, Control.PRESET_BOTTOM_LEFT, 16, -168, 300, 160)
	ap.add_theme_stylebox_override("panel", hd._panel_style(Color(0.04, 0.03, 0.09, 0.92), Color(0.3, 0.8, 1.0, 0.6)))
	hd.hud.add_child(ap)
	hd.attr_rt = _rt(15)
	ap.add_child(hd.attr_rt)
	hd.stats_panel = PanelContainer.new()
	hd._place(hd.stats_panel, Control.PRESET_CENTER_LEFT, 16, -302, 360, 420)
	hd.stats_panel.add_theme_stylebox_override("panel", hd._panel_style(Color(0.03, 0.02, 0.08, 0.95), Color(0.3, 0.8, 1.0, 0.8)))
	hd.stats_panel.visible = false
	hd.hud.add_child(hd.stats_panel)
	hd.stats_rt = _rt(15)
	hd.stats_panel.add_child(hd.stats_rt)
	var ip := PanelContainer.new()
	hd._place(ip, Control.PRESET_BOTTOM_RIGHT, -244, -168, 228, 160)
	ip.add_theme_stylebox_override("panel", hd._panel_style(Color(0.04, 0.03, 0.09, 0.92), Color(1.0, 0.8, 0.3, 0.6)))
	hd.hud.add_child(ip)
	var iv := VBoxContainer.new()
	iv.add_theme_constant_override("separation", 4)
	ip.add_child(iv)
	var top := HBoxContainer.new()
	iv.add_child(top)
	gold_lbl = hd._label(20, Color(1.0, 0.82, 0.25))
	gold_lbl.custom_minimum_size = Vector2(110, 0)
	top.add_child(gold_lbl)
	var shop_btn := _small_btn("商店 (B)", 96)
	shop_btn.pressed.connect(func(): _close_shop() if shop_open else _open_shop())
	top.add_child(shop_btn)
	var igrid := GridContainer.new()
	igrid.columns = 3
	igrid.add_theme_constant_override("h_separation", 6)
	igrid.add_theme_constant_override("v_separation", 6)
	iv.add_child(igrid)
	for i in 6:
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(66, 50)
		b.expand_icon = true
		b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.add_theme_stylebox_override("normal", hd._panel_style(Color(0.08, 0.07, 0.14), Color(0.3, 0.3, 0.45)))
		b.add_theme_stylebox_override("hover", hd._panel_style(Color(0.15, 0.12, 0.25), Color(1.0, 0.85, 0.3)))
		b.add_theme_stylebox_override("pressed", hd._panel_style(Color(0.15, 0.12, 0.25), Color(1.0, 0.85, 0.3)))
		b.gui_input.connect(_on_inv_input.bind(i))
		igrid.add_child(b)
		inv_slots.append(b)
	shop = PanelContainer.new()
	hd._place(shop, Control.PRESET_BOTTOM_RIGHT, -620, -612, 604, 436)
	shop.add_theme_stylebox_override("panel", hd._panel_style(Color(0.03, 0.02, 0.07, 0.96), Color(1.0, 0.8, 0.3, 0.9)))
	shop.visible = false
	hd.hud.add_child(shop)
	var sv := VBoxContainer.new()
	sv.add_theme_constant_override("separation", 6)
	shop.add_child(sv)
	var head := HBoxContainer.new()
	sv.add_child(head)
	var title := hd._label(22, Color(1.0, 0.85, 0.35))
	title.text = "商店"
	title.custom_minimum_size = Vector2(70, 0)
	head.add_child(title)
	for tab in [["basic", "基础"], ["advanced", "进阶"], ["ultimate", "终极"], ["upgrade", "英雄强化"]]:
		var tb := _small_btn(tab[1], 96)
		tb.pressed.connect(_set_shop_tab.bind(tab[0]))
		head.add_child(tb)
		shop_tabs[tab[0]] = tb
	shop_gold = hd._label(18, Color(1.0, 0.82, 0.25), HORIZONTAL_ALIGNMENT_RIGHT)
	shop_gold.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(shop_gold)
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(588, 214)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sv.add_child(sc)
	shop_grid = GridContainer.new()
	shop_grid.columns = 8
	shop_grid.add_theme_constant_override("h_separation", 6)
	shop_grid.add_theme_constant_override("v_separation", 6)
	sc.add_child(shop_grid)
	var hint := hd._label(12, Color(0.7, 0.7, 0.85))
	hint.text = "⏸ 商店打开时游戏暂停 · 左/右键购买 · 已有配件自动合成 · 右键物品栏出售（返还 50%）"
	sv.add_child(hint)
	shop_detail = _rt(14)
	shop_detail.custom_minimum_size = Vector2(588, 120)
	sv.add_child(shop_detail)

func _set_shop_tab(tab: String) -> void:
	shop_tab = tab
	vw.sfx("select", 1.4, -12.0)
	_rebuild_shop_grid()

func _rebuild_shop_grid() -> void:
	for c in shop_grid.get_children():
		c.queue_free()
	for id in ItemsDB.ORDER:
		var it: Dictionary = ItemsDB.DB[id]
		if it["cat"] != shop_tab: continue
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(66, 70)
		b.icon = gm.TEX["it_" + str(id)]
		b.expand_icon = true
		b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
		b.text = str(int(it["cost"]))
		b.add_theme_font_override("font", vw.ui_font)
		b.add_theme_font_size_override("font_size", 15)
		b.add_theme_color_override("font_color", Color(1.0, 0.82, 0.25))
		b.add_theme_stylebox_override("normal", hd._panel_style(Color(0.08, 0.07, 0.14), Color(0.3, 0.3, 0.45)))
		b.add_theme_stylebox_override("hover", hd._panel_style(Color(0.15, 0.12, 0.25), Color(1.0, 0.85, 0.3)))
		b.add_theme_stylebox_override("pressed", hd._panel_style(Color(0.25, 0.18, 0.05), Color(1.0, 0.85, 0.3)))
		b.set_meta("id", id)
		b.pressed.connect(_buy.bind(str(id)))
		b.gui_input.connect(_on_shop_input.bind(str(id)))
		b.mouse_entered.connect(_shop_hover_set.bind(str(id)))
		shop_grid.add_child(b)
	for k in shop_tabs:
		(shop_tabs[k] as Button).modulate = Color(1.3, 1.2, 0.7) if k == shop_tab else Color(0.8, 0.8, 0.9)
	_refresh_shop()

func _shop_hover_set(id: String) -> void:
	shop_hover = id
	shop_detail.text = _item_text(id, true)

func _open_shop() -> void:
	if gm.state != C.S.PLAY: return
	shop_open = true
	shop.visible = true
	inp.targeting = ""
	inp.right_held = false
	_rebuild_shop_grid()
	vw.sfx("select", 1.2, -8.0)

func _close_shop() -> void:
	shop_open = false
	if shop:
		shop.visible = false

func _refresh_shop() -> void:
	if not shop_open or gm.player == null: return
	shop_gold.text = "金钱 %d" % int(gm.player.gold)
	for b in shop_grid.get_children():
		if not b.has_meta("id"): continue
		var id: String = b.get_meta("id")
		var price := gm.shop_price_for(gm.player, id)
		var it: Dictionary = ItemsDB.DB[id]
		var locked: bool = it["special"].has("shard") and gm.player.shard_owned
		(b as Button).text = ("已装配" if locked else str(price))
		(b as Button).modulate = Color(1, 1, 1) if (gm.player.gold >= price and not locked) else Color(0.5, 0.5, 0.55)
	if shop_hover != "":
		shop_detail.text = _item_text(shop_hover, true)

func _refresh_inv() -> void:
	if gm.player == null: return
	for i in 6:
		var b: Button = inv_slots[i]
		if i < gm.player.inv.size():
			var id: String = gm.player.inv[i]
			b.icon = gm.TEX["it_" + id]
			var refund: bool = gm.rounds != null and gm.player.refund_tokens > 0
			b.tooltip_text = _strip_bb(_item_text(id, false)) + "\n右键出售（返还 %d 金%s）" % [int(float(ItemsDB.DB[id]["cost"]) * (1.0 if refund else 0.5)), "，本回合原价" if refund else ""]
		else:
			b.icon = null
			b.tooltip_text = "空栏位"

var _ui_t := 0.0
func _update_ui_v3(delta: float) -> void:
	var p := gm.player
	gold_lbl.text = "金 %d" % int(p.gold)
	_ui_t -= delta
	if _ui_t > 0.0: return
	_ui_t = 0.25
	if shop_open:
		_refresh_shop()
	if gm.autopilot:
		_refresh_inv()
	var g := func(k: String) -> float: return float(p.ST.get(k, 0.0))
	var dfp := func(x: float) -> int: return int(round((1.0 - gm.def_mult(x)) * 100.0))
	hd.attr_rt.text = "攻击力 %d [color=#6aff8a]+%d[/color]   攻速 %d%%（%.2f 秒）\n物防 %d（减伤 %d%%）  法防 %d（减伤 %d%%）\n技能强度 %d%%   冷却缩减 %d%%\n移速 %d   吸血 %d%%\n[color=#8a92b8]按 C 查看详细属性[/color]" % [
		int(p.atk_base_display()), int(p.atk_bonus_display()), int(round(p.atk_rate() * 100.0)), p.atk_interval(),
		int(p.armor_val()), dfp.call(p.armor_val()), int(p.mr_val()), dfp.call(p.mr_val()),
		int(round(g.call("pow") * 100.0)), int(round(g.call("cdr") * 100.0)),
		int(p.move_speed()), int(round(g.call("ls") * 100.0))]
	if hd.stats_panel.visible:
		var crit: Array = p.sp().get("crit", [0.0, 1.0])
		var upg := []
		if p.shard_owned: upg.append("特化芯片")
		if p.has_scepter(): upg.append("终极协议")
		hd.stats_rt.text = "[b][color=#ffd23f]%s[/color][/b]   [color=#8a92b8]英雄面板固定，属性全部来自装备与符文；升级只获得技能点[/color]\n\n攻击力  %d + [color=#6aff8a]%d[/color]%s\n攻击速度  %d%%（攻击间隔 %.2f 秒，英雄基础 %.2f 秒）\n攻击距离  %d%s    弹道速度  %d    视野  %d\n物理防御  %d（物理减伤 %d%%）\n法术防御  %d（法术减伤 %d%%）\n移动速度  %d\n生命  %d    回复 %.1f / 秒\n法力  %d    回复 %.1f / 秒\n技能强度  %d%%    冷却缩减  %d%%    吸血  %d%%\n暴击  %s\n英雄强化  %s" % [
			p.def["name"],
			int(p.atk_base_display()), int(p.atk_bonus_display()), ("  [color=#ffd23f](双倍伤害神符)[/color]" if p.dd_t > 0.0 else ""),
			int(round(p.atk_rate() * 100.0)), p.atk_interval(), float(p.def["stats"]["interval"]), int(p.atk_range()), ("（近战）" if bool(p.def["melee"]) else ""),
			int(p.proj_speed()), int(g.call("vision")),
			int(p.armor_val()), dfp.call(p.armor_val()), int(p.mr_val()), dfp.call(p.mr_val()), int(p.move_speed()),
			int(p.max_hp), p.hp_regen(), int(p.mana_max), p.mp_regen(),
			int(round(g.call("pow") * 100.0)), int(round(g.call("cdr") * 100.0)), int(round(g.call("ls") * 100.0)),
			("%d%% 几率 ×%s" % [int(crit[0] * 100), _num(crit[1])]) if crit[0] > 0.0 else "无",
			"、".join(PackedStringArray(upg)) if not upg.is_empty() else "无"]
