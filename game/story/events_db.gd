extends RefCounted
## Story content (M2): the original history (原本轨迹), choice events, generic events, past-life notes (前世笔记) and
## endings. Pure data in the vocabulary of game/story/rules.gd. Rules: docs/design/角色机制设计.md 第四节,
## docs/design/角色设计规范.md; the story: docs/design/角色设定初稿_第一赛季.md.
##
## TIMELINE entry: {"id", "owner" (character id or "world"), "s": season, "at": "pre" | "w<N>" (start of week N) | "po"
##   (playoffs start) | "end" (season over, before the off-season) | "off" (off-season), "if": [conditions], "p": chance,
##   "do": [effects] | "event": choice event id (offered to the player when the human club is involved, otherwise the
##   choice marked "past" is taken), "result": [conditions] judged after the choice (did the original outcome happen),
##   "check": true = only observes (e.g. who wins), "news": text when it happens}
## Conditions are states, not "event X happened", so the world keeps working when history diverges.

const TIMELINE := [
	# ---------------- S1
	{"id": "bear_family", "owner": "bear", "s": 1, "at": "w5", "if": [["team_of", "bear", "spark"], ["contract_pay", "bear", "<=", "low"]],
		"p": 1.0, "event": "bear_family_call"},
	{"id": "bear_quit", "owner": "bear", "s": 1, "at": "off", "p": 0.9,
		"if": [["team_of", "bear", "spark"], ["not", ["flag", "bear_stayed"]], ["any", [["flag", "bear_leaving"], ["team_rank", "spark", ">=", 5]]]],
		"do": [["retire", "bear"]], "news": "{bear} 退役，回家帮忙打理早餐店。"},
	{"id": "fish_offer", "owner": "fish", "s": 1, "at": "off", "if": [["team_of", "fish", "spark"]], "p": 1.0, "event": "fish_sky_offer",
		"result": [["team_of", "fish", "sky"]]},
	{"id": "sky_s1_title", "owner": "world", "s": 1, "at": "end", "check": true, "if": [["champion", "pro", "sky"]]},
	{"id": "zp_s1_up", "owner": "world", "s": 1, "at": "end", "check": true, "if": [["champion", "sec", "zp"]]},
	# ---------------- S2
	{"id": "qin_to_sky", "owner": "qin", "s": 2, "at": "pre", "if": [["staff_free", "qin"]], "p": 1.0,
		"do": [["coach", "qin", "sky"]], "news": "天穹宣布前雷霆主教练{qin}出任主教练。"},
	{"id": "rin_to_aur", "owner": "rin", "s": 2, "at": "pre", "if": [["free_agent", "rin"]], "p": 0.95,
		"do": [["move", "rin", "aur"]], "news": "极光签下 16 岁的天才少女{rin}。"},
	{"id": "king_benched", "owner": "king", "s": 2, "at": "w4", "if": [["team_of", "king", "aur"], ["team_of", "rin", "aur"]], "p": 1.0,
		"do": [["satisfaction", "king", -30], ["respect", "king", -20], ["flag", "king_benched"]], "news": "极光开始让新人{rin}首发，老将{king}的位置岌岌可危。"},
	{"id": "rex_fallout", "owner": "rex", "s": 2, "at": "w4", "if": [["team_of", "rex", "rf"]], "p": 0.9,
		"do": [["satisfaction", "rex", -35], ["flag", "rex_unhappy"]], "news": "{rex} 与赤焰续约谈判破裂，双方公开互相指责。"},
	{"id": "owl_unpaid", "owner": "world", "s": 2, "at": "w6", "if": [["league_of", "owl", "pro"]], "p": 0.9,
		"do": [["flag", "owl_broke"]], "news": "夜枭被曝拖欠选手工资已经三个月。"},
	{"id": "king_retire", "owner": "king", "s": 2, "at": "off", "if": [["team_of", "king", "aur"], ["flag", "king_benched"]], "p": 0.85,
		"do": [["retire", "king"]], "news": "{king} 宣布退役：「我只是想再打一年。」"},
	{"id": "rex_to_sky", "owner": "rex", "s": 2, "at": "off", "if": [["team_of", "rex", "rf"], ["flag", "rex_unhappy"]], "p": 0.9,
		"do": [["move", "rex", "sky"]], "news": "{rex} 加盟天穹，天穹为他配了专职翻译。"},
	{"id": "owl_fold", "owner": "world", "s": 2, "at": "off", "if": [["flag", "owl_broke"], ["not", ["human_team", "ghost"]]], "p": 1.0,
		"do": [["fold", "owl"], ["retire", "ghost"]], "news": "夜枭被转卖，全队解散重组；队长{ghost}转行做了主播。"},
	# ---------------- S3
	{"id": "rock_to_ds", "owner": "rock", "s": 3, "at": "pre", "if": [["free_agent", "rock"]], "p": 0.95,
		"do": [["move", "rock", "ds"]], "news": "深空签下一名在工厂打工的年轻坦克{rock}。"},
	{"id": "mute_to_phm", "owner": "mute", "s": 3, "at": "pre", "if": [["free_agent", "mute"]], "p": 0.95,
		"do": [["move", "mute", "phm"]], "news": "幻影签下神秘的网络辅助{mute}。"},
	{"id": "taro_breakout", "owner": "taro", "s": 3, "at": "pre", "if": [["team_of", "taro", "ds"]], "p": 0.9,
		"do": [["attr", "taro", "all", 1], ["potential", "taro", 1], ["fame", "taro", 15]], "news": "深空的{taro}在休赛期突飞猛进，拿下首发位置。"},
	{"id": "sulian_crash", "owner": "world", "s": 3, "at": "w4", "if": [], "p": 1.0,
		"do": [["flag", "sulian_crash"]], "news": "赞助商「速联科技」资金链断裂，拖欠多支战队的赞助费。"},
	{"id": "phm_scandal", "owner": "world", "s": 3, "at": "po", "if": [["league_of", "phm", "pro"], ["not", ["flag", "phm_reported"]]], "p": 0.9,
		"do": [["retire", "vex"], ["suspend_team", "phm", 8], ["relegate", "phm"], ["flag", "phm_scandal"]],
		"news": "幻影假赛丑闻曝光：{vex} 终身禁赛，全队停赛调查，战队被逐出职业联赛。钱总下落不明。"},
	{"id": "sky_s3_title", "owner": "world", "s": 3, "at": "end", "check": true, "if": [["champion", "pro", "sky"]]},
	# ---------------- S4 / S5
	{"id": "rock_rise", "owner": "rock", "s": 4, "at": "pre", "if": [["team_of", "rock", "ds"]], "p": 0.85,
		"do": [["attr", "rock", "all", 1], ["fame", "rock", 20]], "news": "深空的{rock}被评为最被看好的坦克。"},
	{"id": "sky_s4_title", "owner": "world", "s": 4, "at": "end", "check": true, "if": [["champion", "pro", "sky"]]},
	{"id": "sky_s5_title", "owner": "world", "s": 5, "at": "end", "check": true, "if": [["champion", "pro", "sky"]]},
]

## choice events. "past": the choice the original history took (used when the AI decides, and by the replay test)
const EVENTS := {
	"bear_family_call": {"kind": "major", "show": "phone_chat", "who": "bear",
		"text": "{bear}：阿驰……我妈又打电话了，家里的早餐店忙不过来，我爸身体也不好。她让我别打了，回去帮忙。",
		"choices": [
			{"label": "给他加薪", "effects": [["contract_pay", "bear", "mid"], ["persona", "bear", "loyalty", 1], ["satisfaction", "bear", 15], ["flag", "bear_stayed"]]},
			{"label": "周末去他家帮忙，一起说服家里", "effects": [["rel", "bear", "hero_pc", 15], ["fatigue", "hero_pc", 15], ["satisfaction", "bear", 10], ["flag", "bear_stayed"]]},
			{"label": "尊重他的决定，赛季结束后放他走", "past": true, "effects": [["flag", "bear_leaving"], ["form", "fish", -1], ["rel", "fish", "hero_pc", -10]]},
		]},
	"fish_sky_offer": {"kind": "major", "show": "phone_chat", "who": "fish",
		"text": "{fish}：哥……天穹找我了，开的工资是这里的三倍。他们说我去了能学到很多……我该去吗？",
		"choices": [
			{"label": "留下来，我们一起打上去", "effects": [["persona", "fish", "loyalty", 1], ["satisfaction", "fish", 10], ["news", "{fish} 婉拒天穹的报价，留在{spark}。"]]},
			{"label": "收下转会费，放他去天穹", "past": true, "effects": [["move", "fish", "sky"], ["money", 3000], ["form", "bear", -2], ["news", "{fish} 加盟天穹。"]]},
			{"label": "让他自己决定", "effects": [["chain", "fish_decides"]]},
		]},
	"fish_decides": {"kind": "minor", "show": "phone_chat", "who": "fish", "auto": true,
		"text": "{fish} 想了一整晚。",
		"branches": [
			{"if": [["satisfaction", "fish", ">=", 60], ["rel", "fish", "hero_pc", ">=", 40]], "effects": [["news", "{fish}：我不走了。这里才是我的队。"], ["persona", "fish", "loyalty", 1]]},
			{"if": [], "effects": [["move", "fish", "sky"], ["money", 3000], ["news", "{fish} 还是选择了天穹。"]]},
		]},
	# ---------------- generic (state-driven) events offered to the player; $p / $q = the people involved
	"gen_transfer_request": {"kind": "major", "show": "phone_chat", "who": "$p",
		"text": "{$p}：我想换个环境。如果有队要我，希望你放我走。",
		"choices": [
			{"label": "同意，把他挂牌（解约成为自由身）", "past": true, "effects": [["release", "$p"], ["news", "{$p} 与战队解约。"]]},
			{"label": "找他谈心，承诺更多机会", "effects": [["satisfaction", "$p", 20], ["respect", "$p", 10]]},
			{"label": "不理会", "effects": [["satisfaction", "$p", -10], ["form", "$p", -1]]},
		]},
	"gen_bench_unhappy": {"kind": "minor", "show": "phone_chat", "who": "$p",
		"text": "{$p}：已经好几周没上场了……我是不是哪里做得不好？",
		"choices": [
			{"label": "安抚他：下场给你机会", "effects": [["satisfaction", "$p", 8], ["respect", "$p", 5]]},
			{"label": "让他继续等", "past": true, "effects": [["satisfaction", "$p", -5]]},
		]},
	"gen_homesick": {"kind": "minor", "show": "phone_chat", "who": "$p",
		"text": "{$p} 最近总是一个人发呆，翻看家乡的照片。",
		"choices": [
			{"label": "带他去吃家乡菜", "effects": [["satisfaction", "$p", 10], ["lang", "$p", "zh", 1]]},
			{"label": "放两天假", "past": true, "effects": [["fatigue", "$p", -20], ["satisfaction", "$p", 5]]},
		]},
	"gen_quarrel": {"kind": "major", "show": "phone_chat", "who": "$p",
		"text": "训练室里，{$p} 和 {$q} 吵起来了，差点动手。",
		"choices": [
			{"label": "各打五十大板", "past": true, "effects": [["rel", "$p", "$q", 10], ["respect", "$p", -5], ["respect", "$q", -5]]},
			{"label": "站在 {$p} 这边", "effects": [["rel", "$p", "$q", -5], ["satisfaction", "$p", 8], ["satisfaction", "$q", -12]]},
			{"label": "让他们自己解决", "effects": [["rel", "$p", "$q", 2]]},
		]},
	"gen_tired": {"kind": "minor", "show": "phone_chat", "who": "$p",
		"text": "{$p} 的黑眼圈越来越重，训练时一直在打哈欠。",
		"choices": [
			{"label": "强制休息", "effects": [["fatigue", "$p", -25]]},
			{"label": "坚持一下", "past": true, "effects": [["fatigue", "$p", 5], ["form", "$p", 0.5]]},
		]},
}

## generic events: checked every week for every player (pair = for every two teammates). The human club gets the
## choice event; AI clubs take "ai" effects. cool = weeks before the same person can get it again.
const GENERIC := [
	{"id": "gen_transfer_request", "who": "player", "if": [["satisfaction", "$p", "<", 30], ["persona", "$p", "ambition", ">=", 6]], "p": 0.5, "cool": 6,
		"ai": [["release", "$p"], ["news", "{$p} 因不满出场时间与{$t}解约。"]]},
	{"id": "gen_bench_unhappy", "who": "player", "if": [["bench_streak", "$p", ">=", 3], ["persona", "$p", "ambition", ">=", 7]], "p": 0.6, "cool": 4,
		"ai": [["satisfaction", "$p", -5]]},
	{"id": "gen_homesick", "who": "player", "if": [["comm_low", "$p", 2], ["satisfaction", "$p", "<", 65]], "p": 0.25, "cool": 8,
		"ai": [["satisfaction", "$p", 5]]},
	{"id": "gen_quarrel", "who": "pair", "if": [["rel", "$p", "$q", "<", -30]], "p": 0.3, "cool": 6, "ai": [["rel", "$p", "$q", 5]]},
	{"id": "gen_tired", "who": "player", "if": [["fatigue", "$p", ">=", 80]], "p": 0.7, "cool": 3, "ai": [["fatigue", "$p", -15]]},
]

## past-life notes. bind = timeline entry; when = "start" | "season:N" | "week:N" (S1 week N) | "meet:<id>" (the human
## club plays the person's club, or the person joins it) | "recall" (only by an effect)
const NOTES := [
	{"id": "n_sky_s1", "bind": "sky_s1_title", "when": "start", "clear": true, "text": "S1 职业联赛冠军是天穹，Zero 拿了决赛 MVP。"},
	{"id": "n_zp_up", "bind": "zp_s1_up", "when": "start", "clear": true, "text": "S1 次级联赛冠军是零点，他们那年升级了。"},
	{"id": "n_bear", "bind": "bear_quit", "when": "start", "clear": true, "text": "大熊 S1 之后就退役了，因为家里缺钱。"},
	{"id": "n_fish", "bind": "fish_offer", "when": "start", "clear": true, "text": "天穹签小鱼只是为了不让别人签，他在那边三年没上过场。"},
	{"id": "n_rin", "bind": "rin_to_aur", "when": "start", "clear": true, "text": "极光 S2 签了一个 16 岁的女孩 Rin，当年就拿了新人王。"},
	{"id": "n_qin", "bind": "qin_to_sky", "when": "week:3", "clear": true, "text": "秦岚这时候明明是自由身……S2 她去了天穹，天穹的王朝就是她带出来的。"},
	{"id": "n_owl", "bind": "owl_fold", "when": "start", "clear": true, "text": "夜枭 S2 撑不下去了，欠了选手好几个月工资，赛季结束就散了。"},
	{"id": "n_phm", "bind": "phm_scandal", "when": "start", "clear": true, "text": "幻影 S3 出事，假赛，钱总跑路了。离他们远点。"},
	{"id": "n_rex", "bind": "rex_to_sky", "when": "season:2", "clear": true, "text": "Rex S2 中期和赤焰闹翻，休赛期去了天穹。"},
	{"id": "n_king", "bind": "king_retire", "when": "meet:king", "clear": false, "text": "King S2 被极光换下来后，好像赛季末就退役了。"},
	{"id": "n_rock", "bind": "rock_to_ds", "when": "meet:rock", "clear": false, "text": "深空 S3 签的那个坦克阿岩……好像以前就在我们网吧玩过？"},
	{"id": "n_mute", "bind": "mute_to_phm", "when": "meet:mute", "clear": false, "text": "幻影那个被禁赛的辅助 Mute，听说是被 Vex 拉下水的，她其实很干净。"},
	{"id": "n_taro", "bind": "taro_breakout", "when": "meet:taro", "clear": false, "text": "深空 S3 那个辅助 Taro，之前一直坐板凳。"},
	{"id": "n_sky_dyn", "bind": "sky_s3_title", "when": "season:2", "clear": true, "text": "天穹从 S3 开始三连冠。"},
	{"id": "n_sulian", "bind": "sulian_crash", "when": "season:2", "clear": false, "text": "速联科技……好像 S3 出过事，拖欠了很多队的钱。"},
]

## endings of the core characters: the first that matches, judged at the end of a career
const ENDINGS := {
	"bear": [{"text": "星火的定海神针", "if": [["team_of", "bear", "spark"], ["season", ">=", 3]]},
		{"text": "退役回家，经营早餐店", "if": [["retired", "bear"]]}, {"text": "另谋出路", "if": []}],
	"fish": [{"text": "顶级辅助", "if": [["attr_avg", "fish", ">=", 14]]},
		{"text": "重蹈覆辙，在天穹坐了几年板凳", "if": [["team_of", "fish", "sky"]]}, {"text": "平凡的职业生涯", "if": []}],
	"zero": [{"text": "依旧站在顶点", "if": [["fame", "zero", ">=", 85]]}, {"text": "王座易主", "if": []}],
	"rin": [{"text": "星火的双核之一", "if": [["team_of", "rin", "spark"]]}, {"text": "联赛顶级输出", "if": [["attr_avg", "rin", ">=", 14]]},
		{"text": "天才陨落", "if": []}],
	"rex": [{"text": "天穹王朝的一块拼图", "if": [["team_of", "rex", "sky"]]}, {"text": "为星火而战", "if": [["team_of", "rex", "spark"]]},
		{"text": "辗转各队的雇佣兵", "if": []}],
	"king": [{"text": "老将的最后一舞", "if": [["not", ["retired", "king"]]]}, {"text": "退役做了解说", "if": []}],
	"mute": [{"text": "走出房间的天才", "if": [["team_of", "mute", "spark"]]}, {"text": "被假赛案毁掉", "if": [["flag", "phm_scandal"], ["suspended", "mute"]]},
		{"text": "无人知晓的天才", "if": []}],
}
