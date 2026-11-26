extends RefCounted
## The fixed world (固定世界): clubs, core characters and the named regular players of season 1.
## Pure data. Format and rules: docs/design/角色设计规范.md; the story behind it: docs/design/角色设定初稿_第一赛季.md.
## Player attrs order: reaction, mechanics, awareness, decision, teamwork, composure (1..20).
## persona order: ambition, loyalty, greed, pride, social (0..10).
## Regular players without explicit numbers get them from game/league/world.gd build_fixed() with the fixed CAST_SEED,
## so they are the same in every run; only the realised potential and the walk-on youth (路人) change per run.

const CAST_SEED := 20261126
const PROTAGONIST := "hero_pc"
const HUMAN_TEAM := "spark"
## the 4th player of 星火: one of these (前世记忆里的名字) or a walk-on, chosen at the start of a career
const CANDIDATES := ["rin", "rock", "mute"]

## league "pro" = 职业联赛 (international), "sec" = 次级联赛. mean = ability mean of generated regular players.
const TEAMS := {
	"sky": {"name": "天穹", "short": "SKY", "league": "pro", "tier": 1, "mean": 13.0, "col": Color(0.5, 0.95, 0.95)},
	"aur": {"name": "极光", "short": "AUR", "league": "pro", "tier": 1, "mean": 13.0, "col": Color(0.6, 1.0, 0.6)},
	"rf": {"name": "赤焰", "short": "RF", "league": "pro", "tier": 2, "mean": 11.0, "col": Color(1.0, 0.45, 0.3)},
	"ds": {"name": "深空", "short": "DS", "league": "pro", "tier": 2, "mean": 11.0, "col": Color(0.55, 0.5, 1.0)},
	"thd": {"name": "雷霆", "short": "THD", "league": "pro", "tier": 2, "mean": 11.0, "col": Color(1.0, 0.85, 0.3)},
	"phm": {"name": "幻影", "short": "PHM", "league": "pro", "tier": 2, "mean": 11.0, "col": Color(0.85, 0.5, 1.0)},
	"owl": {"name": "夜枭", "short": "OWL", "league": "pro", "tier": 3, "mean": 9.6, "col": Color(0.75, 0.55, 0.35)},
	"tdl": {"name": "狂澜", "short": "TDL", "league": "pro", "tier": 3, "mean": 9.6, "col": Color(0.3, 0.6, 0.9)},
	"spark": {"name": "星火", "short": "SPK", "league": "sec", "tier": 3, "mean": 10.0, "col": Color(1.0, 0.6, 0.25)},
	"zp": {"name": "零点", "short": "ZP", "league": "sec", "tier": 3, "mean": 11.8, "col": Color(0.9, 0.9, 0.95)},
	"iw": {"name": "钢铁意志", "short": "IW", "league": "sec", "tier": 3, "mean": 10.3, "col": Color(0.7, 0.75, 0.8)},
	"sr": {"name": "星环", "short": "SR", "league": "sec", "tier": 3, "mean": 9.4, "col": Color(0.4, 0.7, 1.0)},
	"hbr": {"name": "港湾", "short": "HBR", "league": "sec", "tier": 3, "mean": 9.0, "col": Color(0.35, 0.85, 0.75)},
	"ns": {"name": "北极星", "short": "NS", "league": "sec", "tier": 3, "mean": 8.8, "col": Color(0.8, 0.85, 1.0)},
	"rfx": {"name": "赤狐", "short": "RFX", "league": "sec", "tier": 3, "mean": 8.8, "col": Color(1.0, 0.55, 0.45)},
	"blg": {"name": "白鲸", "short": "BLG", "league": "sec", "tier": 3, "mean": 8.5, "col": Color(0.85, 0.95, 1.0)},
}

## core players (核心角色) with full data
const CORE := {
	"hero_pc": {"name": "江驰", "handle": "Ash", "role": "carry", "team": "spark", "slot": "starter", "gender": "m", "nation": "CN",
		"langs": {"zh": 3, "en": 1}, "age": 19, "attrs": [13, 14, 10, 8, 9, 8], "potential": [16, 18], "curve": "standard",
		"focus": ["awareness", "decision"], "prof": {"drift": 85, "blade": 60, "ember": 45, "falcon": 30}, "sig": {"drift": ""},
		"persona": [9, 7, 3, 8, 6], "fame": 3, "contract": [1, "low"], "tagline": "重来一次的人"},
	"bear": {"name": "熊磊", "handle": "大熊", "role": "tank", "team": "spark", "slot": "starter", "gender": "m", "nation": "CN",
		"langs": {"zh": 3}, "age": 21, "attrs": [8, 9, 10, 9, 13, 11], "potential": [13, 15], "curve": "late",
		"focus": ["awareness", "teamwork"], "prof": {"anchor": 82, "aegis": 55, "frost": 40, "rail": 25}, "sig": {"anchor": "anchor_wide_hook"},
		"persona": [3, 9, 6, 4, 8], "fame": 2, "contract": [1, "low"], "tagline": "网吧里最能扛的胖子"},
	"fish": {"name": "余晓", "handle": "小鱼", "role": "support", "team": "spark", "slot": "starter", "gender": "m", "nation": "CN",
		"langs": {"zh": 3, "en": 2}, "age": 18, "attrs": [11, 12, 11, 10, 12, 6], "potential": [15, 17], "curve": "standard",
		"focus": ["awareness", "composure"], "prof": {"seer": 78, "tide": 60, "lumen": 45, "echo": 30}, "sig": {"seer": ""},
		"persona": [5, 7, 4, 6, 6], "fame": 3, "contract": [1, "low"], "tagline": "天赋最好、最怕输的那个"},
	"rin": {"name": "苏凛", "handle": "Rin", "role": "carry", "team": "", "slot": "free", "gender": "f", "nation": "CN",
		"langs": {"zh": 3, "en": 2}, "age": 16, "attrs": [14, 12, 8, 7, 6, 9], "potential": [17, 20], "curve": "early",
		"focus": ["mechanics", "reaction"], "prof": {"falcon": 70, "drift": 55, "ember": 40, "blade": 20}, "sig": {"falcon": ""},
		"persona": [10, 3, 4, 9, 3], "fame": 0, "contract": [0, "low"], "tagline": "冷着脸打出最狠操作的少女"},
	"rock": {"name": "石岩", "handle": "阿岩", "role": "tank", "team": "", "slot": "free", "gender": "m", "nation": "CN",
		"langs": {"zh": 3}, "age": 17, "attrs": [8, 8, 9, 10, 10, 13], "potential": [16, 19], "curve": "late",
		"focus": ["awareness", "decision"], "prof": {"rail": 72, "frost": 50, "aegis": 40, "anchor": 35}, "sig": {"rail": ""},
		"persona": [5, 8, 7, 3, 7], "fame": 0, "contract": [0, "low"], "tagline": "夜班后来网吧练到天亮的人"},
	"mute": {"name": "沈默", "handle": "Mute", "role": "support", "team": "", "slot": "free", "gender": "f", "nation": "CN",
		"langs": {"zh": 3, "en": 2}, "age": 17, "attrs": [12, 11, 14, 12, 4, 8], "potential": [17, 19], "curve": "standard",
		"focus": ["teamwork", "awareness"], "prof": {"echo": 74, "seer": 50, "lumen": 40, "tide": 30}, "sig": {"echo": ""},
		"persona": [6, 6, 2, 5, 1], "fame": 0, "contract": [0, "low"], "tagline": "看得最透、话说得最少的人"},
	"zero": {"name": "凌霄", "handle": "Zero", "role": "carry", "team": "sky", "slot": "starter", "gender": "m", "nation": "CN",
		"langs": {"zh": 3, "en": 2}, "age": 20, "attrs": [16, 17, 15, 15, 13, 16], "potential": [17, 19], "curve": "standard",
		"focus": ["teamwork", "awareness"], "prof": {"ember": 90, "falcon": 85, "drift": 70, "blade": 50}, "sig": {"ember": "ember_twin_blast", "falcon": ""},
		"persona": [10, 5, 5, 10, 4], "fame": 80, "contract": [3, "top"], "tagline": "前世站在顶点的那个人"},
	"king": {"name": "金正勋", "handle": "King", "role": "carry", "team": "aur", "slot": "starter", "gender": "m", "nation": "KR",
		"langs": {"ko": 3, "zh": 2, "en": 1}, "age": 28, "attrs": [11, 13, 16, 16, 14, 15], "potential": [14, 15], "curve": "early",
		"focus": ["awareness", "decision"], "prof": {"blade": 88, "drift": 80, "ember": 55, "falcon": 40}, "sig": {"blade": "", "drift": ""},
		"persona": [6, 8, 4, 7, 9], "fame": 70, "contract": [1, "high"], "tagline": "用脑子打比赛的老将"},
	"rex": {"name": "Rafael Souza", "handle": "Rex", "role": "tank", "team": "rf", "slot": "starter", "gender": "m", "nation": "BR",
		"langs": {"pt": 3, "en": 1}, "age": 22, "attrs": [13, 13, 12, 11, 10, 12], "potential": [14, 16], "curve": "standard",
		"focus": ["mechanics", "reaction"], "prof": {"frost": 88, "aegis": 75, "anchor": 50, "rail": 40}, "sig": {"frost": "frost_cold_aura", "aegis": ""},
		"persona": [6, 2, 10, 7, 4], "fame": 55, "contract": [1, "high"], "tagline": "谁给钱多就为谁拼命"},
	"taro": {"name": "陶然", "handle": "Taro", "role": "support", "team": "ds", "slot": "bench", "gender": "f", "nation": "SG",
		"langs": {"zh": 3, "en": 3}, "age": 19, "attrs": [10, 10, 13, 12, 14, 10], "potential": [15, 17], "curve": "late",
		"focus": ["awareness", "teamwork"], "prof": {"lumen": 80, "tide": 55, "seer": 50, "echo": 35}, "sig": {"lumen": ""},
		"persona": [4, 7, 3, 2, 9], "fame": 8, "contract": [2, "low"], "tagline": "坐在板凳上的未来决赛辅助"},
	"ghost": {"name": "郭奇", "handle": "Ghost", "role": "carry", "team": "owl", "slot": "starter", "gender": "m", "nation": "CN",
		"langs": {"zh": 3}, "age": 24, "attrs": [10, 11, 10, 10, 12, 9], "potential": [11, 12], "curve": "standard",
		"focus": ["teamwork", "decision"], "prof": {"blade": 82, "drift": 60, "ember": 45, "falcon": 35}, "sig": {"blade": ""},
		"persona": [4, 10, 2, 5, 9], "fame": 25, "contract": [2, "mid"], "tagline": "穷队里最讲义气的大哥"},
}

## named regular players (常规角色): numbers are generated around the club's mean with CAST_SEED
const REGULAR := {
	"tower": {"handle": "Tower", "role": "tank", "team": "sky", "slot": "starter", "gender": "m", "nation": "KR", "age": 25, "langs": {"ko": 3, "zh": 2}},
	"lux": {"handle": "Lux", "role": "support", "team": "sky", "slot": "starter", "gender": "f", "nation": "CN", "age": 22},
	"kite": {"handle": "Kite", "role": "carry", "team": "sky", "slot": "bench", "gender": "m", "nation": "US", "age": 19, "langs": {"en": 3}},
	"bolt": {"handle": "Bolt", "role": "tank", "team": "aur", "slot": "starter", "gender": "m", "nation": "CN", "age": 23},
	"polar": {"handle": "Polar", "role": "support", "team": "aur", "slot": "starter", "gender": "f", "nation": "SE", "age": 21, "langs": {"sv": 3, "en": 3, "zh": 1}, "boost": 1.5},
	"jin": {"handle": "Jin", "role": "support", "team": "aur", "slot": "bench", "gender": "m", "nation": "KR", "age": 18, "langs": {"ko": 3, "zh": 1}},
	"match": {"handle": "火柴", "role": "carry", "team": "rf", "slot": "starter", "gender": "m", "nation": "CN", "age": 20},
	"moss": {"handle": "Moss", "role": "support", "team": "rf", "slot": "starter", "gender": "f", "nation": "VN", "age": 24, "langs": {"vi": 3, "zh": 2}},
	"pixel": {"handle": "Pixel", "role": "tank", "team": "rf", "slot": "bench", "gender": "f", "nation": "CN", "age": 18},
	"wall": {"handle": "石墙", "role": "tank", "team": "ds", "slot": "starter", "gender": "m", "nation": "CN", "age": 26},
	"volt": {"handle": "Volt", "role": "carry", "team": "ds", "slot": "starter", "gender": "m", "nation": "DE", "age": 23, "langs": {"de": 3, "en": 3, "zh": 1}},
	"hex": {"handle": "Hex", "role": "support", "team": "ds", "slot": "starter", "gender": "f", "nation": "CN", "age": 25},
	"ox": {"handle": "铁牛", "role": "tank", "team": "thd", "slot": "starter", "gender": "m", "nation": "CN", "age": 24},
	"leo": {"handle": "Leo", "role": "carry", "team": "thd", "slot": "starter", "gender": "m", "nation": "US", "age": 22, "langs": {"en": 3, "zh": 1}},
	"sol": {"handle": "Sol", "role": "support", "team": "thd", "slot": "starter", "gender": "f", "nation": "BR", "age": 21, "langs": {"pt": 3, "en": 2, "zh": 1}},
	"dash": {"handle": "Dash", "role": "carry", "team": "thd", "slot": "bench", "gender": "m", "nation": "CN", "age": 19},
	"jet": {"handle": "Jet", "role": "tank", "team": "phm", "slot": "starter", "gender": "m", "nation": "CN", "age": 22},
	"vex": {"handle": "Vex", "role": "carry", "team": "phm", "slot": "starter", "gender": "m", "nation": "CN", "age": 23},
	"yuki": {"handle": "Yuki", "role": "support", "team": "phm", "slot": "starter", "gender": "f", "nation": "JP", "age": 20, "langs": {"ja": 3, "zh": 2, "en": 1}},
	"zed": {"handle": "Zed", "role": "tank", "team": "phm", "slot": "bench", "gender": "m", "nation": "RU", "age": 18, "langs": {"ru": 3, "en": 1}},
	"cat": {"handle": "老猫", "role": "tank", "team": "owl", "slot": "starter", "gender": "m", "nation": "CN", "age": 27},
	"mint": {"handle": "Mint", "role": "support", "team": "owl", "slot": "starter", "gender": "f", "nation": "CN", "age": 19},
	"chime": {"handle": "风铃", "role": "support", "team": "owl", "slot": "bench", "gender": "f", "nation": "CN", "age": 17},
	"rocky": {"handle": "磐石", "role": "tank", "team": "tdl", "slot": "starter", "gender": "m", "nation": "CN", "age": 24},
	"nova": {"handle": "Nova", "role": "carry", "team": "tdl", "slot": "starter", "gender": "f", "nation": "US", "age": 20, "langs": {"en": 3, "zh": 1}},
	"kui": {"handle": "小葵", "role": "support", "team": "tdl", "slot": "starter", "gender": "f", "nation": "CN", "age": 18},
	"rook": {"handle": "Rook", "role": "tank", "team": "tdl", "slot": "bench", "gender": "m", "nation": "PH", "age": 19, "langs": {"en": 3, "tl": 3}},
}

## staff and other people (no match numbers yet; coaches have a placeholder skill)
const STAFF := {
	"qin": {"name": "秦岚", "handle": "秦岚", "kind": "coach", "team": "", "gender": "f", "nation": "CN", "age": 29,
		"skill": "bp_master", "persona": [8, 6, 4, 6, 7], "tagline": "被老板开除的最好的教练"},
	"zhou": {"name": "周建国", "handle": "老周", "kind": "owner", "team": "spark", "gender": "m", "nation": "CN", "age": 52,
		"persona": [3, 9, 3, 4, 8], "tagline": "抠门、嘴硬、心软的网吧老板"},
	"qian": {"name": "钱满", "handle": "钱总", "kind": "owner", "team": "phm", "gender": "m", "nation": "CN", "age": 45,
		"persona": [9, 2, 10, 8, 5], "tagline": "一掷千金的金主，钱来路不明"},
	"ake": {"name": "阿珂", "handle": "阿珂", "kind": "media", "team": "", "gender": "f", "nation": "CN", "age": 26,
		"persona": [6, 5, 5, 6, 9], "tagline": "毒舌但讲理的解说"},
}

## coach skills (placeholder until the coach system): bp_master = the team drafts without mistakes
const COACH_SKILLS := {"bp_master": {"name": "禁选大师", "draft_noise": 0.0}}

## relations at the start (both directions). lv 1..3; conflict types are negative.
const LINKS := [
	["hero_pc", "bear", "brother", 3], ["hero_pc", "fish", "brother", 3], ["bear", "fish", "friend", 2],
	["hero_pc", "zero", "rival", 3], ["zero", "lux", "friend", 2], ["zero", "qin", "mentor", 2],
	["rex", "sol", "friend", 2], ["king", "jin", "mentor", 2], ["fish", "polar", "admire", 1],
	["mute", "vex", "rival", 1], ["hero_pc", "zhou", "boss", 2], ["ghost", "cat", "friend", 2],
	["qin", "ox", "rival", 2], ["rex", "match", "rival", 1], ["taro", "hex", "rival", 1],
	["rin", "king", "rival", 1], ["rin", "zero", "admire", 1], ["rock", "bear", "admire", 1], ["mute", "fish", "rival", 1],
	["taro", "polar", "friend", 1], ["ghost", "hero_pc", "friend", 1], ["king", "zero", "rival", 2], ["rex", "tower", "rival", 1], ["rock", "hero_pc", "friend", 1],
]
const LINK_VALUE := {"brother": 30, "friend": 25, "mentor": 20, "admire": 15, "boss": 15, "rival": -25}

## name pools for the generated players (次级联赛 and walk-ons), by nation
const NAMES_ZH := ["阿星", "小白", "夜鹰", "风行", "冷月", "疾风", "青石", "火羽", "星辰", "白鹭", "阿杰", "小米", "木鱼", "老K", "阿飞",
	"小满", "七七", "阿宁", "南风", "北辰", "糖糖", "阿酒", "橙子", "小林", "阿哲", "石头", "可乐", "一一", "雪球", "黑猫", "阿瑶", "晴天"]
const NAMES_INT := {"KR": ["Han", "Seo", "Doran", "Minji", "Kael"], "US": ["Ace", "Ryder", "Skye", "Max"], "JP": ["Haru", "Mei", "Ren"],
	"BR": ["Tico", "Luna"], "VN": ["Bao", "Linh"], "DE": ["Felix", "Mira"], "TH": ["Nam", "Ploy"], "AU": ["Jett", "Ivy"]}
const NATION_LANG := {"CN": "zh", "KR": "ko", "US": "en", "JP": "ja", "BR": "pt", "VN": "vi", "DE": "de", "SE": "sv", "RU": "ru", "SG": "zh", "PH": "tl", "TH": "th", "AU": "en"}
const NATION_NAMES := {"CN": "中国", "KR": "韩国", "US": "美国", "JP": "日本", "BR": "巴西", "VN": "越南", "DE": "德国", "SE": "瑞典", "RU": "俄罗斯",
	"SG": "新加坡", "PH": "菲律宾", "TH": "泰国", "AU": "澳大利亚"}
const LANG_NAMES := {"zh": "中文", "en": "英语", "ko": "韩语", "ja": "日语", "pt": "葡萄牙语", "vi": "越南语", "de": "德语", "sv": "瑞典语", "ru": "俄语", "tl": "他加禄语", "th": "泰语"}
