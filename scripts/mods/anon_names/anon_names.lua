-- chunkname: @scripts/mods/anon_names/anon_names.lua
--[[
	匿名名池 (Anon Names) v1.2.1
	Author: CiJhuiDi

	AnonPlayers 的附属：把它给出的掩码换成中文意象化名。

	判定（A 方案，2026-10-12 收口 —— **只有一条规则**）：
	    profile 属于「我账号下的角色」 → 放行真名
	    确证不属于                    → 换化名
	    判定不了                      → 什么都不做（返回上游结果）
	不再回读上游的「他人」设置、也不再猜 `masked == real_name` 是什么含义 ——
	旧版把判据叠成五层，v1.0.1 / v1.0.3 两次「修一个引入一个」都出在那里。
	已知代价：不再跟随 AnonPlayers 的「其他账户名称 / 其他玩家」设置（设成「不匿名」时
	本 mod 依然会化名）。本 mod 的定位就是「别人一律化名」。

	接入的出口：
	  * AnonPlayers 的 mod.anonymize —— 它 8 个 CLASS 钩子都从这一处出结果
	    （PlayerInfo.character_name / user_display_name、RemotePlayer.name / character_name、
	      HumanPlayer.name、BotPlayer.name、PresenceEntry*.character_name、profile_utils.character_name）
	  * presence 的 account_name —— AnonPlayers 完全没覆盖，实测会返回真名（Huanyan#6301 这种）
	  * 头顶名牌 —— vanilla 模板**直接读 profile.name**，绕过全部钩子
	    （做法：在模板 update_function 里、vanilla 取数之前把 profile.name 换成化名；
	      改 widget 会与 vanilla 每帧互相覆盖 → 名牌疯狂闪烁）

	调试入口见文件尾「诊断后门」一节（debug_state / debug_explain / debug_trace / ...）。
	同一玩家全程同一个化名（key 统一到 account_id + 哈希结果缓存）。
]]

local mod = get_mod("anon_names")

-- ##########################################################
-- ################## 化名池 ################################
-- 字形约束（硬性）：池子里的字必须落在 **GB2312 一级字库（16-55 区，3755 个常用字）**内。
-- 游戏中文字体是 Noto Sans SC 的「游戏子集」（见 scripts/managers/ui/ui_fonts_definitions.lua：
-- zh-cn → noto_sans_sc_bold / noto_sans_sc_black），二级字（次常用字）会渲染成方块 ——
-- 实测距星「氐/觜/昴/轸宿一」就是这样变成「□宿一」的，为此删掉了 63 个含二级字的名字。
--
-- 刻意**不依赖任何「CJK 字体修复 mod」**：本 mod 应当在任何字体环境下都不出方块，
-- 而不是把「能不能用」变成别人 mod 的函数。
--
-- 往池子里加名字后必须跑 `暗潮\tools\check_anon_pool.py`，
-- 它按一级字库逐字校验，非一级字会直接报出所在的池与名字。
-- ##########################################################

local SOLAR_TERMS = {
	"立春", "雨水", "惊蛰", "春分", "清明", "谷雨",
	"立夏", "小满", "芒种", "夏至", "小暑", "大暑",
	"立秋", "处暑", "白露", "秋分", "寒露", "霜降",
	"立冬", "小雪", "大雪", "冬至", "小寒", "大寒",
}

-- 花草分五大类，每类都是独立的风格选项；flora = 五类合并
local FLORA_FLOWER = {
	-- 花木
	"梅花", "兰花", "翠竹", "秋菊", "牡丹", "芍药", "海棠", "玉兰", "丁香",
	"桂花", "山茶", "杜鹃", "含笑", "月季",
	"百合", "石竹", "雏菊", "莲花", "睡莲", "水仙", "兰草", "迎春", "瑞香",
	"结香", "绣球", "龙胆", "麦冬", "文竹", "吊兰", "绿萝", "木棉", "合欢",
	"槐花", "梨花", "桃花", "杏花", "樱花", "桔梗", "铃兰", "木香",
	"紫荆", "腊梅", "垂丝海棠", "西府海棠", "贴梗海棠", "榆叶梅", "郁李", "紫叶李",
	"美人梅", "珍珠梅", "绣线菊", "琼花", "天女花", "辛夷", "白兰", "黄兰",
	"太平花",
}

local FLORA_HERB = {
	-- 草本
	"薄荷", "紫苏", "艾草", "蒲公英", "车前草", "芦苇", "白茅", "狗尾草", "含羞草",
	"三叶草", "芭蕉", "香蒲", "忍冬", "连翘",
	"佩兰", "泽兰", "茵陈", "鱼腥草", "夏枯草",
	"益母草", "灯心草", "凤仙", "锦葵", "秋葵", "罗勒", "迷迭香", "百里香",
	"牛至", "鼠尾草", "香茅", "紫花地丁", "白头翁", "威灵仙", "金线莲",
	"半枝莲", "垂盆草", "佛甲草", "积雪草",
}

local FLORA_VINE = {
	-- 藤蔓
	"紫藤", "凌霄", "葡萄", "常春藤", "爬山虎", "藤萝", "金银花", "牵牛花", "探春",
	"络石", "木通", "五味子", "铁线莲", "使君子", "炮仗花", "西番莲", "三角梅",
	"扶芳藤", "地锦", "葛藤", "鸡血藤", "夜来香", "球兰", "百香果", "飘香藤", "山葡萄",
	"蛇葡萄", "禾雀花", "紫珠", "南蛇藤",
}

local FLORA_TREE = {
	-- 树木
	"银杏", "梧桐", "香樟", "青松", "翠柏", "垂柳", "红枫", "云杉", "白榆",
	"古槐", "桑叶", "紫檀", "苏铁", "罗汉松", "红豆杉", "香椿",
	"水杉", "侧柏", "圆柏", "雪松", "油松", "马尾松", "冷杉", "泡桐",
	"朴树", "黄连木", "枫香", "广玉兰", "冬青", "女贞",
	"凤凰木", "白蜡", "五角枫", "元宝枫", "油茶", "核桃", "板栗",
	"石榴", "杨梅", "樱桃",
}

local FLORA_GARDEN = {
	-- 园艺花卉
	"矢车菊", "金鱼草", "美女樱", "马鞭草", "万寿菊", "孔雀草", "风铃草", "蓝铃花", "紫罗兰",
	"向日葵", "满天星", "风信子", "郁金香", "波斯菊", "秋海棠", "君子兰", "蟹爪兰",
	"矮牵牛", "长寿花", "非洲菊", "玛格丽特", "小苍兰", "朱顶红", "番红花",
	"雪滴花", "报春花", "仙客来", "大岩桐", "金盏菊", "蛇目菊", "松果菊", "天人菊",
	"黑心菊", "金光菊", "百日草", "千日红", "鸡冠花", "雁来红", "醉蝶花",
	"羽衣甘蓝", "香雪球", "飞燕草", "剪秋罗",
}

-- 中国传统星名（星官名 + 序号）。名单取自香港太空馆「中国星区、星官及星名英译表」
-- （基于《仪象考成》体系），并已人工筛选：
--   * 剔除凶名与不雅名（积尸、天屎、厕、哭、泣、坟墓、败瓜、天谗、屠肆、折威、狗国…）
--     —— 队友顶着「天屎」出现在名牌上不合适
--   * 剔除四象与星区名（青龙、白虎、朱雀、玄武、十二国）和单字宿名（角、亢、氐…）
--   * 剔除生僻字与近南极里易生歧义的（鈇钺、天棓、瓠瓜、十字架…）
-- 序号按星官内的排列顺序，不按亮度（所以参宿七比参宿一亮得多）。
-- 注意「南门」星官只有两颗星（南门一 = 半人马座β、南门二 = 半人马座α），
-- 不存在「南门三」—— 别照着这个思路编名字。
local STAR = {
	-- 二十八宿距星
	"角宿一", "亢宿一", "房宿一", "心宿一", "尾宿一", "箕宿一",
	"斗宿一", "牛宿一", "女宿一", "虚宿一", "危宿一", "室宿一", "壁宿一",
	"奎宿一", "娄宿一", "胃宿一", "毕宿一", "参宿一", "井宿一",
	"鬼宿一", "柳宿一", "星宿一", "张宿一", "翼宿一",
	-- 北斗七星（各有专名，不带序号）
	"天枢", "天权", "玉衡", "开阳", "摇光",
	-- 著名亮星
	"天狼", "老人", "大角", "织女一", "河鼓二", "天津四", "心宿二", "毕宿五",
	"轩辕十四", "北落师门", "五车二", "南门一", "南门二", "参宿二", "参宿三",
	"参宿四", "参宿七", "天船三", "天大将军一", "奎宿九", "娄宿三", "弧矢一",
	"弧矢七", "尾宿八", "房宿三",
	-- 三垣星官名
	"紫微", "太微", "天市", "北极", "勾陈", "华盖", "阁道", "天床", "天厨",
	"尚书", "女史", "御女", "天柱", "三公", "天纪",
	"文昌", "内阶", "传舍", "天枪", "玄戈", "天理", "太尊", "天乙", "太乙",
	"内厨", "四辅", "六甲", "三师", "大理", "阴德", "九卿", "内屏",
	"明堂", "灵台", "长垣", "少微", "常陈", "郎位", "郎将", "幸臣",
	"从官", "三台", "帝座", "市楼", "宗正", "宗人", "车骑", "骑官", "女床",
	"贯索", "七公",
	-- 二十八宿下辖星官
	"进贤", "库楼", "周鼎", "阳门", "亢池", "帝席", "梗河", "招摇", "天乳",
	"天辐", "键闭", "东咸", "西咸", "神宫", "傅说", "左旗",
	"右旗", "离珠", "扶筐", "司命", "司禄", "司非", "天垒城", "盖屋",
	"虚梁", "天钱", "车府", "造父", "天钩", "离宫", "雷电", "垒壁阵",
	"羽林军", "天纲", "八魁", "云雨", "王良", "附路", "军南门", "外屏",
	"左更", "右更", "大陵", "天船", "天河", "卷舌", "天苑", "附耳", "天街",
	"天高", "诸王", "天关", "天节", "参旗", "天园", "司怪", "座旗", "玉井",
	"南河", "北河", "军市", "丈人", "天社", "天狗",
	"酒旗", "天相", "天庙", "青丘", "军门", "长沙", "咸池",
	-- 近南极星官（明代据西方星表补入）
	"孔雀", "金鱼", "飞鱼", "蜜蜂", "海山", "海石", "水委", "蛇首", "蛇尾",
	"小斗", "南船", "火鸟", "马尾",
}

-- 拼接工具：FLORA 和 MIXED 都要用，所以定义在它们之前
local function append_all(dst, src)
	for _, name in ipairs(src) do
		dst[#dst + 1] = name
	end
end

-- 全部花草（五大类合并）
local FLORA = {}
append_all(FLORA, FLORA_FLOWER)
append_all(FLORA, FLORA_HERB)
append_all(FLORA, FLORA_VINE)
append_all(FLORA, FLORA_TREE)
append_all(FLORA, FLORA_GARDEN)

-- 全部混合：节气 + 花草 + 星名（想要大池子、少撞名就选它）
local MIXED = {}
append_all(MIXED, SOLAR_TERMS)
append_all(MIXED, FLORA)
append_all(MIXED, STAR)

local POOLS = {
	jieqi = SOLAR_TERMS,
	flora = FLORA,
	flower = FLORA_FLOWER,
	herb = FLORA_HERB,
	vine = FLORA_VINE,
	tree = FLORA_TREE,
	garden = FLORA_GARDEN,
	star = STAR,
	mixed = MIXED,
}

-- ##########################################################
-- ################## 化名分配 ##############################
-- 纯哈希取模，零状态：同一个 key 永远得到同一个化名，所以同一玩家全程同名；
-- 不同 key 允许撞名 —— 刻意不维护占用表 / 回收 / 去重。
-- 这样「池子耗尽、集体重排、局内换名」这些问题在设计上就不存在
--（原 mod 的「机器人名称」模式也是同一个思路）。

-- djb2 是线性哈希：只差一个字符的两个 key（例如机器人的 "bot:1"/"bot:2"）
-- 只会得到差一个常数的哈希值，取模后落进**相邻索引** —— 4 个机器人会整齐拿到
-- 「房宿三/紫微/太微/天市」，甚至一组连号的距星「角宿一/亢宿一/氐宿一/房宿一」。
-- 所以补一轮非线性混合把相邻输入打散（实测索引跨度从 3 提升到 85+）。
-- 精度注意：Lua 数字是 double（53 位尾数），必须先压到 26 位再平方，
-- 26+26=52 位不丢精度；直接对 32 位平方会到 2^64，结果就失真了。
local function mix32(h)
	h = h % 67108864
	h = (h * h) % 4294967296
	h = (h * 40503) % 4294967296
	h = h % 67108864
	h = (h * h) % 4294967296
	h = (h * 40503) % 4294967296

	return h
end

local function hash_string(text)
	local h = 5381

	for i = 1, #text do
		h = (h * 33 + string.byte(text, i)) % 4294967296
	end

	return mix32(h)
end

-- character_id → account_id 映射。
-- 为什么需要：不同路径传进来的 profile **携带的 id 不一样** ——
-- presence / players 的 profile 只有 character_id（account_id = nil），
-- 而带账号维度的出口（account_name、hook_origin 版 user_display_name）能给出 account_id。
-- 只按「account_id 优先」取 key，同一个玩家就会在两处拿到**两个不同的化名**。
-- 2026-10-09 用户实测「同一个人的名字多处不一样」，活体复现（同一 cid）：
--     只有 character_id          → 秋菊
--     character_id + account_id  → 含笑
-- 所以这里先把 cid → account_id 补齐，让**所有路径**解析到同一个 key。
local character_accounts = {}
local account_map_logged = false
local last_account_map_refresh = -math.huge
local ACCOUNT_MAP_REFRESH_INTERVAL = 3

local function refresh_character_accounts()
	local now = os.time and os.time() or nil

	if now and (now - last_account_map_refresh) < ACCOUNT_MAP_REFRESH_INTERVAL then
		return
	end

	last_account_map_refresh = now or 0

	local presence = Managers.presence
	local by_account = presence and presence._presences_by_account_id

	if type(by_account) == "table" then
		for account_id, entry in pairs(by_account) do
			if type(account_id) == "string" and account_id ~= "" then
				local ok, profile = pcall(function ()
					return entry:character_profile()
				end)
				local character_id = ok and type(profile) == "table" and profile.character_id

				if type(character_id) == "string" and character_id ~= "" then
					character_accounts[character_id] = account_id
				end
			end
		end
	end

	local player_manager = Managers.player

	if player_manager and type(player_manager.players) == "function" then
		local ok, players = pcall(function ()
			return player_manager:players()
		end)

		if ok and type(players) == "table" then
			for _, player in pairs(players) do
				local profile = player and player._profile
				local character_id = type(profile) == "table" and profile.character_id

				if type(character_id) == "string" and character_id ~= "" and type(player.account_id) == "function" then
					local ok_acc, account_id = pcall(function ()
						return player:account_id()
					end)

					if ok_acc and type(account_id) == "string" and account_id ~= "" then
						character_accounts[character_id] = account_id
					end
				end
			end
		end
	end

	-- 只报一次，便于从日志判断映射有没有真正建起来（诊断用）
	if not account_map_logged then
		local count = 0

		for _ in pairs(character_accounts) do
			count = count + 1
		end

		if count > 0 then
			account_map_logged = true
			mod:info("[anon_names] cid->account_id map built (%d entries)", count)
		end
	end
end

-- key：**统一到 account_id**（同一个人跨角色、跨界面只用同一个化名）。
--   * profile 直接带 account_id → 顺手记下 cid→account_id 映射，用 account_id
--   * 只带 character_id → 查映射补全；补不到才退回 character_id（并催一次映射刷新）
--   * 都没有 → 真名字符串兜底
-- 账号名与角色名共用这一套 key。
local function alias_key(profile, real_name, is_account)
	if type(profile) == "table" then
		local character_id = profile.character_id
		local account_id = profile.account_id
		local has_character_id = type(character_id) == "string" and character_id ~= ""
		local has_account_id = type(account_id) == "string" and account_id ~= ""

		if has_character_id and has_account_id then
			character_accounts[character_id] = account_id

			return account_id
		end

		if has_character_id then
			local mapped = character_accounts[character_id]

			if not mapped then
				refresh_character_accounts()
				mapped = character_accounts[character_id]
			end

			return mapped or character_id
		end

		if has_account_id then
			return account_id
		end
	end

	if type(real_name) == "string" and real_name ~= "" then
		return (is_account and "acc:" or "name:") .. real_name
	end

	return nil
end

-- 唯一的分配逻辑：哈希取模。不查表、不记录、不重试。
-- v1.0.6 加一层「key → 化名」缓存：名字查询是**每帧级**的（日志实测单个玩家约 95 次/秒），
-- 而 hash_string 每次都要把 key 逐字节跑一遍 djb2 + 两轮 mix32；缓存后只剩一次表查找。
-- 池子（风格）换了整体失效，结果与纯哈希完全一致（同一 key 永远同一个化名）。
local ALIAS_CACHE_LIMIT = 4000
local alias_cache = {}
local alias_cache_pool = nil
local alias_cache_count = 0

local function alias_for(key, pool)
	if alias_cache_pool ~= pool then
		alias_cache = {}
		alias_cache_pool = pool
		alias_cache_count = 0
	end

	local alias = alias_cache[key]

	if alias then
		return alias
	end

	alias = pool[(hash_string(key) % #pool) + 1]

	if alias_cache_count >= ALIAS_CACHE_LIMIT then
		alias_cache = {}
		alias_cache_count = 0
	end

	alias_cache[key] = alias
	alias_cache_count = alias_cache_count + 1

	return alias
end

-- ##########################################################
-- ################## 机器人判定 ############################
-- 机器人没有隐私可言（名字是游戏预置的，不是玩家名），要不要也给它化名由设置决定。
-- 判据用 profile 引用反查 player_manager 的 bot 列表：源码实证
--   PlayerManager.add_bot_player(...) 显式传 account_id = nil（真人走 add_human_player）
--   bot._profile 就是 hook 收到的同一个 profile 引用 —— 引用比对百分之百可靠
--   客户端同样成立：create_players_from_sync_data 按 is_human_controlled 分流
-- 命中时返回稳定 key：用槽位 id 而不是 profile 里的名字，因为 BotPlayer.name() 会先
-- 返回 _debug_name（"Bot Player 1"）再变成预置名，拿名字当 key 会让同一局内换化名。

-- bot_key 的结果按 profile 缓存（弱键）。profile 与「是不是机器人」的对应关系在一局内不会变，
-- 而这个名字查询是 hot path（实测约 95 次/秒/玩家）—— 省掉每次的 pcall + bot_players() + next()。
-- 存 false 表示「确认不是机器人」，与「还没查过（nil）」区分开。
local bot_key_cache = setmetatable({}, { __mode = "k" })

local function bot_key(profile)
	if not profile then
		return nil
	end

	local cached = bot_key_cache[profile]

	if cached ~= nil then
		return cached or nil
	end

	local player_manager = Managers.player

	if not player_manager or type(player_manager.bot_players) ~= "function" then
		return nil
	end

	local ok, bots = pcall(function ()
		return player_manager:bot_players()
	end)

	if not ok or type(bots) ~= "table" then
		return nil
	end

	-- 绝大多数场合没有机器人：先短路，省掉下面的 pairs 遍历
	if next(bots) == nil then
		bot_key_cache[profile] = false

		return nil
	end

	for unique_id, bot in pairs(bots) do
		if bot and bot._profile == profile then
			local key = "bot:" .. tostring(bot._local_player_id or unique_id)
			bot_key_cache[profile] = key

			return key
		end
	end

	bot_key_cache[profile] = false

	return nil
end

-- ##########################################################
-- ################## 上游放行的甄别 ########################
-- 上游 AnonPlayers 决定「谁该被匿名」，本 mod 只跟随。但它的 is_me 判据是**短路**的：
--
--     local is_me = Managers.ui and Managers.ui:view_active("main_menu_view") or _is_my_profile(profile)
--
-- 也就是「只要 main_menu_view 处于激活状态，任何 profile 都被当成我」。
-- 后果：在主菜单看别人的角色名时，上游拿**我自己**的两个设置（anon_me / anon_my_account，
-- 默认都是 0 = 不匿名）去裁决 → 直接 return real_name，真名穿透到社交 / 最近玩家列表。
-- 本 mod 原来的判据是 `masked == real_name` 就当作「上游决定不匿名」照抄，于是跟着一起泄漏。
--
-- 2026-10-09 实测（dt-cli 把 view_active("main_menu_view") 临时伪装成 true）：
--     基线：      别人角色名 → 化名「含羞草」
--     伪装主菜单：别人角色名 → 真名（上游 is_me 短路 + anon_me = 0）
--
-- 所以这里补一层甄别（**三态**，见 local_profile_state）：上游返回真名时
--   * 确实是我 → 放行（尊重 anon_me / anon_my_account = 0）
--   * **确证是别人** → 回头读上游的「他人」设置（anon_others / anon_other_accounts）重新裁决：
--       该匿名就换化名；显式设 0（不匿名他人）时仍照抄
--   * 判定不了（拿不到本机档案 / profile 缺 id）→ **放行**，什么都不动
-- 这样既不覆盖用户的显式设置、又不误伤自己，同时堵住主菜单那条泄漏路径。
-- 该分支只在「上游放行真名」时才进入，平时零开销。
--
-- v1.0.1 曾把「判定不了」当成「不是我」，结果把玩家自己的名字也匿名了（v1.0.2 修）。

-- ##########################################################
-- ################## 「我的角色」集合 ######################
-- 让「这是不是我」从「猜」变成**决定性**判断。
--
-- 为什么需要：角色选择界面里**未选中的、同一个账号下的其他角色**，character_id 与当前角色不同。
-- 只比 local_player 的 cid 会把它误判成「别人」→ 拿 anon_others 去裁决 → 我自己的其他角色被化名
--（2026-10-09 用户实测反馈）。
--
-- Managers.data_service.profiles:fetch_all_profiles() 返回本账号全部角色，实测结构：
--     { gear = ..., selected_profile = { character_id = <当前角色> },
--       profiles = { [1..7] = { character_id = "...", name = "CJDYZ..." } } }
-- 缓存成集合后判据就确定了：
--     cid 在集合里        → **是我**（含未选中的其他角色）
--     cid 不在集合里      → **确证是别人**（集合涵盖本账号全部角色）
-- 集合没加载好之前不下这种结论，退回下面的保守判据。
local my_character_ids = {}
local my_characters_loaded = false
local characters_logged = false
local last_character_refresh = -math.huge
local CHARACTER_REFRESH_INTERVAL = 10

-- 只在「游戏世界已就绪」之后才拉角色列表。
-- fetch_all_profiles() 解析失败时会 `Managers.error:report_error(BackendError)` —— 会弹错误、
-- 游戏直接进 error state；而**启动早期 master data 还没就绪**，正是它最容易失败的时机
--（2026-10-09 日志实证：14:06:17 一次 BackendError，
--  profiles_service.lua:196 ← master_items.lua:117 `rawget` got nil）。
-- 游戏自己的 account_service 也会调它，但我们没必要在最危险的窗口里插一脚；
-- 更关键的是：那一次失败会让本 mod 的「我的角色」集合建不起来 → 判据退化成 nil → **放行真名**。
-- 取本机玩家。**必须用 local_player_safe**：
-- local_player() 直接走 Network.peer_id()，在连接初始化之前调用会**在 native 层崩溃**，
-- pcall 拦不住 C 层崩溃（崩溃日志栈顶就是 `[C]: in function peer_id`）。游戏自己为此
-- 提供了 safe 版，它会先查 Managers.connection:is_initialized()。
-- 2026-10-10 实证：mod.update 从第一帧开始轮询 → local_player(1) → crash dump。
local function get_local_player()
	local player_manager = Managers.player

	if not player_manager or type(player_manager.local_player_safe) ~= "function" then
		return nil
	end

	local ok, local_player = pcall(function ()
		return player_manager:local_player_safe(1)
	end)

	if ok then
		return local_player
	end

	return nil
end

local function game_world_ready()
	local local_player = get_local_player()

	return local_player ~= nil and local_player._profile ~= nil
end

-- 本机身份（当前出战角色 + 账号 id），缓存 1 秒。
-- 判定在 hot path 上（日志实测单个玩家约 95 次/秒），不能每次都走一遍 local_player_safe。
-- 换角色后最多 1 秒内仍按旧身份判定，可以接受（界面刷新远快于这个量级）。
local identity_cache = { profile = nil, account_id = nil, at = -1 }
local IDENTITY_TTL = 1

local function local_identity()
	local now = os.time and os.time() or nil

	if identity_cache.profile and now and identity_cache.at >= 0 and (now - identity_cache.at) < IDENTITY_TTL then
		return identity_cache
	end

	identity_cache.profile = nil

	local local_player = get_local_player()

	if local_player then
		identity_cache.profile = local_player._profile

		if type(local_player.account_id) == "function" then
			local ok, account_id = pcall(function ()
				return local_player:account_id()
			end)

			if ok and type(account_id) == "string" and account_id ~= "" then
				identity_cache.account_id = account_id
			end
		end
	end

	-- 世界还没起来时，presence 的「我自己」仍可能给出账号 id
	if not identity_cache.account_id then
		local presence = Managers.presence
		local myself = presence and presence._myself

		if myself and type(myself.account_id) == "function" then
			local ok, account_id = pcall(function ()
				return myself:account_id()
			end)

			if ok and type(account_id) == "string" and account_id ~= "" then
				identity_cache.account_id = account_id
			end
		end
	end

	identity_cache.at = now or -1

	return identity_cache
end

local function refresh_my_characters()
	if my_characters_loaded or not game_world_ready() then
		return
	end

	local now = os.time and os.time() or nil

	if now and (now - last_character_refresh) < CHARACTER_REFRESH_INTERVAL then
		return
	end

	last_character_refresh = now or 0

	local data_service = Managers.data_service
	local service = data_service and data_service.profiles

	if not service or type(service.fetch_all_profiles) ~= "function" then
		return
	end

	local ok, promise = pcall(function ()
		return service:fetch_all_profiles()
	end)

	if not ok or type(promise) ~= "table" or type(promise.next) ~= "function" then
		return
	end

	promise:next(function (data)
		local list = type(data) == "table" and data.profiles

		if type(list) ~= "table" then
			return
		end

		local ids = {}

		for _, profile in pairs(list) do
			local character_id = type(profile) == "table" and profile.character_id

			if type(character_id) == "string" and character_id ~= "" then
				ids[character_id] = true
			end
		end

		my_character_ids = ids
		my_characters_loaded = true

		if not characters_logged then
			characters_logged = true

			local count = 0

			for _ in pairs(ids) do
				count = count + 1
			end

			mod:info("[anon_names] my character set loaded (%d characters)", count)
		end
	end)
end

-- 判定追踪（给诊断后门用，默认关）。关着时只有一次 boolean 判断的开销。
-- trace_record 先声明成空函数，文件尾部的诊断段会把它换成真的实现。
local trace_enabled = false
local trace_buffer = { n = 0 }
local trace_record = function () end

-- ##########################################################
-- ################## 唯一的判定：这是不是我 ##################
-- A 方案（2026-10-12 收口）。旧版把判据叠成了五层：
--     三态判定 / others_masked 回读上游设置 / `masked == real_name` 分支 /
--     窗口期保守回退 / 账号名那套独立判定
-- 每一层都在替「上游为什么返回这个值」做假设 —— v1.0.1 和 v1.0.3 两次
-- 「修一个引入一个」都出在这里（一次误伤自己、一次窗口期放真名）。
--
-- 现在只有一条规则：
--     profile 属于「我账号下的角色」 → 放行真名
--     确证不属于                    → 换化名
--     判定不了                      → 什么都不做（返回上游结果）
--
-- 已知代价（明确接受）：不再跟随上游的「其他账户名称 / 其他玩家」设置 ——
-- 那些设置若设成「不匿名」，本 mod 依然会化名。本 mod 的定位就是「别人一律化名」。
--
-- 三态：true = 我 / false = 确证是别人 / nil = 判定不了。
-- 判据优先级：
--   1. 引用相同（hub / 任务里 hook 收到的就是同一个 profile 表）
--   2. **「我的角色」集合**：在集合里 = 我；集合已加载且不在其中 = 确证是别人
--   3. 集合没加载好时：cid 与本机当前角色不同 → 保守判别人（宁可多化名，不放真名）
--   4. 没有 cid 时退回 account_id 比对
-- 都不成立 → nil。
local function local_profile_state(profile)
	if type(profile) ~= "table" then
		return nil
	end

	local identity = local_identity()
	local my_profile = identity.profile
	local my_account_id = identity.account_id

	if type(my_profile) == "table" and my_profile == profile then
		return true
	end

	local character_id = profile.character_id
	local has_character_id = type(character_id) == "string" and character_id ~= ""

	if has_character_id then
		if my_character_ids[character_id] then
			return true
		end

		-- 先催一次集合加载（内部自带 game_world_ready 守卫 + 10 秒节流）。
		-- **必须放在下面任何 return 之前**：否则「查询到我的非当前角色」这条路径
		-- 永远催不起集合，判据就永远停在保守回退上，把玩家自己的其他角色一直
		-- 判成别人。实测（本机 hub，账号 7 个角色）：直接查其他 6 个 → 全部换成
		-- 池名；先查一次当前角色触发加载，2 秒后同一批角色立刻全部放行。
		-- 加载完成后这里只做一次 boolean 判断，不再进函数（hot path）
		if not my_characters_loaded then
			refresh_my_characters()
		end

		if my_characters_loaded then
			-- 集合里有本账号全部角色，不在其中就是别人 —— 这是修主菜单泄漏的关键一票
			return false
		end

		-- 集合还没建好（启动后那几秒 / 请求失败）：退回 v1.0.2 的判据 ——
		-- 与当前角色不同就**确证是别人**。宁可在这几秒里把「我的其他角色」也化名，
		-- 也不能把真名放出去（2026-10-09 日志实证：启动后 27~36 秒泄漏了 1279 次真名）。
		-- 注意 hub 里 local_player 是**存在**的（就是当前选中的 operative），所以这段
		-- 确实会短暂误伤「我的其他角色」；上面那次 refresh 就是把这个窗口压到最短。
		local mine = type(my_profile) == "table" and my_profile.character_id

		if type(mine) == "string" and mine ~= "" and mine ~= character_id then
			return false
		end
	end

	if type(my_profile) == "table" then
		local mine = my_profile.character_id

		if type(mine) == "string" and mine ~= "" and has_character_id and mine == character_id then
			return true
		end
	end

	if type(my_account_id) == "string" and my_account_id ~= "" then
		local theirs = profile.account_id

		if type(theirs) == "string" and theirs ~= "" then
			return theirs == my_account_id
		end
	end

	return nil
end

-- ##########################################################
-- ################## 账号名兜底 ############################
-- AnonPlayers 只 hook 了 PlayerInfo.user_display_name，**完全没碰 account_name /
-- platform_persona_name_or_account_name**。实测（2026-10-09，hub 里 14 个玩家）：
--     entry:character_name() → 化名 ✓
--     entry:account_name()   → Huanyan#6301（真名）✗
-- 而反编译源码**恰好缺 ui/ 目录**（UI 在字节码里），无法排除界面直接取账号名来显示。
-- 这里用与主路径**同一条规则**补一层：是我 → 放行；否则换化名
--（化名 key 与角色名共用，保证同一个人处处同名）。

local function local_account_id()
	-- presence 的「我自己」最可靠：hub 和主菜单都在
	local presence = Managers.presence
	local myself = presence and presence._myself

	if myself and type(myself.account_id) == "function" then
		local ok, value = pcall(function ()
			return myself:account_id()
		end)

		if ok and type(value) == "string" and value ~= "" then
			return value
		end
	end

	local player_manager = Managers.player

	local local_player = player_manager and get_local_player()

	if local_player and type(local_player.account_id) == "function" then
		local ok_acc, value = pcall(function ()
			return local_player:account_id()
		end)

		if ok_acc and type(value) == "string" and value ~= "" then
			return value
		end
	end

	return nil
end

local function mask_account_name(self, name)
	local style = mod:get("mask_style")
	local pool = POOLS[style]

	if type(name) ~= "string" or name == "" or not style or style == "off" or not pool then
		return name
	end

	local account_id

	if type(self.account_id) == "function" then
		local ok, value = pcall(function ()
			return self:account_id()
		end)

		if ok and type(value) == "string" and value ~= "" then
			account_id = value
		end
	end

	local my_account_id = local_account_id()

	if account_id and my_account_id and account_id == my_account_id then
		return name -- 我自己的账号名
	end

	local profile

	if type(self.character_profile) == "function" then
		local ok, value = pcall(function ()
			return self:character_profile()
		end)

		if ok and type(value) == "table" then
			profile = value
		end
	end

	if profile then
		local state = local_profile_state(profile)

		if state == true then
			return name
		end

		if state == nil and not account_id then
			return name -- 判定不了就不动
		end
	end

	-- 与角色名共用同一套 key（先补 cid→account_id 映射），保证同一个人只有一个化名
	local key_profile = profile

	if type(key_profile) ~= "table" then
		key_profile = { account_id = account_id }
	elseif not key_profile.account_id and account_id then
		key_profile = { character_id = key_profile.character_id, account_id = account_id }
	end

	local key = alias_key(key_profile, name, true)

	if not key then
		return name
	end

	return alias_for(key, pool)
end

local ACCOUNT_NAME_TARGETS = {
	{ "PresenceEntryMyself", "account_name" },
	{ "PresenceEntryImmaterium", "account_name" },
}

local function install_account_name_hooks()
	if mod._account_hooked then
		return true
	end

	local hooked_any = false

	for _, target in ipairs(ACCOUNT_NAME_TARGETS) do
		local class = CLASS[target[1]]

		if class and type(class[target[2]]) == "function" then
			local ok = pcall(function ()
				mod:hook(class, target[2], function (func, self, ...)
					return mask_account_name(self, func(self, ...))
				end)
			end)

			if ok then
				hooked_any = true
			end
		end
	end

	if hooked_any then
		mod._account_hooked = true
		mod:info("[anon_names] hooked presence account_name")
	end

	return hooked_any
end

-- ##########################################################
-- ################## 掩码改写 ##############################

mod.rewrite_mask = function (profile, real_name, is_account, masked)
	local style = mod:get("mask_style")
	local pool = POOLS[style]

	if not style or style == "off" or not pool then
		return masked
	end

	-- 唯一的判定（A 方案，2026-10-12 收口）：
	--   我 → 真名；确证是别人 → 化名；判定不了 → 不介入（返回上游结果）。
	-- 不再回读上游的「他人」设置、也不再猜 `masked == real_name` 是什么含义。
	local mine = local_profile_state(profile)

	-- 默认关闭，这里内联判断，省掉 hot path 上的一次函数调用
	if trace_enabled then
		trace_record(profile, mine, masked)
	end

	if mine == true then
		return real_name
	end

	local bot = bot_key(profile)

	if bot then
		local bot_handling = mod:get("bot_handling")

		if bot_handling == "original" then
			-- 显示游戏预置的机器人名（不是玩家名，直播安全）
			return real_name
		end

		if bot_handling ~= "use_pool" then
			-- 关：保持 AnonPlayers 的处理结果（通常是 ???）
			return masked
		end
	elseif mine == nil then
		-- 判定不了就不动 —— 宁可少藏一层，也不能把玩家自己的名字改掉
		return masked
	end

	-- key：统一到 account_id（同一个人跨角色、跨界面只用同一个化名）
	local key = bot or alias_key(profile, real_name, is_account)

	if not key then
		return masked
	end

	return alias_for(key, pool)
end

-- ##########################################################
-- ################## 接入 AnonPlayers ######################

-- AnonPlayers 全部用点号调用 mod.anonymize(profile, real_name, is_account)，
-- 因此回调里没有隐式 self，直接接三个参数
local function hook_callback(func, profile, real_name, is_account)
	local masked = func(profile, real_name, is_account)

	return mod.rewrite_mask(profile, real_name, is_account, masked)
end

local function install_hook()
	if mod._hooked then
		return true
	end

	local anon_mod = get_mod("AnonPlayers")

	if not anon_mod or type(anon_mod.anonymize) ~= "function" then
		return false
	end

	local original = anon_mod.anonymize

	local ok, err = pcall(function ()
		mod:hook(anon_mod, "anonymize", hook_callback)
	end)

	if not ok then
		mod:warning("[anon_names] hook AnonPlayers.anonymize failed: %s", tostring(err))
		return false
	end

	-- 自检：DMF hook 是立即替换字段，引用没变说明这个版本的 AnonPlayers 不走 mod.anonymize
	if anon_mod.anonymize == original then
		mod:warning("[anon_names] AnonPlayers.anonymize was not replaced; this AnonPlayers version cannot be extended")
		return false
	end

	mod._hooked = true
	mod:info("[anon_names] hooked AnonPlayers.anonymize")

	return true
end

-- 顶层先试一次（日志实证 AnonPlayers 是 load_order_id 26，通常排在本 mod 之前）。
-- 必须用 pcall 包住：get_mod() 由 DML 注入，目标 mod 尚未加载时它可能直接抛错，
-- 一旦抛出来就会中断本文件的加载，连下面的 on_all_mods_loaded 兜底都注册不上。
local ok_early, err_early = pcall(install_hook)

if not ok_early then
	mod:info("[anon_names] early hook skipped: %s", tostring(err_early))
end

-- ##########################################################
-- ################## 头顶名牌兜底 ##########################
-- vanilla 的头顶名牌（hub 与任务各一个模板）**直接读 profile.name**，也就是原始真名；
-- 它不经过 AnonPlayers 的任何钩子，也不经过本 mod 的 rewrite_mask —— 实测同一时刻：
-- bot 的 rewrite_mask 调用 129 次，而人类队友只有 21 次，人类名牌根本不在那条链上。
--
-- 注意**不能**在模板写完之后再去改 widget：vanilla 每帧都会用 profile.name 重写一次，
-- 两边于是每帧互相覆盖、每帧都置 widget.dirty —— 实测表现就是**名牌疯狂闪烁**。
-- 正确做法是在 vanilla 取数**之前**把 profile.name 换成化名，让它自己写出化名。
local NAMEPLATE_TEMPLATE_PATHS = {
	"scripts/ui/hud/elements/world_markers/templates/world_marker_template_nameplate",
	"scripts/ui/hud/elements/world_markers/templates/world_marker_template_nameplate_party_hud",
	"scripts/ui/hud/elements/world_markers/templates/world_marker_template_nameplate_combat",
}

-- 弱键表：记录 profile 的**原始真名**（profile.name 会被我们改写，所以要留底）。
-- 旧实现只记「换成了什么」，于是运行中切风格不再更新、设成「关闭」也不恢复（P2）。
local nameplate_originals = setmetatable({}, { __mode = "k" })

-- 同一个模板表只 hook 一次。mod:hook_require 的回调**每次文件被重新 require 都会重放**
--（DMF 自己的注释也这么说），不守卫就会叠成多层 hook，日志里体现为
-- "Attempting to rehook active hook [update_function]"。
local hooked_nameplate_templates = {}

-- 名牌每帧都会走到这里（在场玩家各一次），而 rewrite_mask 的结果在一局内是稳定的 ——
-- 缓存「profile → { style, masked }」，只有风格变了才重算。
local nameplate_cache = setmetatable({}, { __mode = "k" })

local function mask_profile_name(profile)
	if type(profile) ~= "table" then
		return
	end

	local current = profile.name

	if type(current) ~= "string" or current == "" then
		return
	end

	-- 第一次见到就留底；之后 profile.name 是我们的化名，不能拿它当"真名"再算一遍
	local real = nameplate_originals[profile]

	if not real then
		real = current
		nameplate_originals[profile] = real
	end

	local style = mod:get("mask_style") or "off"
	local cached = nameplate_cache[profile]
	local masked

	if cached and cached.style == style then
		masked = cached.masked
	else
		-- 拿**原真名**重算：切风格自动更新；风格设成「关闭」时 rewrite_mask 会返回原真名，
		-- 于是下面把 profile.name 恢复回去。
		masked = mod.rewrite_mask(profile, real, false, real)

		if type(masked) ~= "string" or masked == "" then
			masked = real
		end

		nameplate_cache[profile] = { style = style, masked = masked }
	end

	if profile.name ~= masked then
		profile.name = masked
	end
end

local function mask_marker_profile(marker)
	local player = marker and marker.data

	if type(player) ~= "table" then
		return
	end

	local profile = player._profile

	if type(profile) == "table" then
		mask_profile_name(profile)

		return
	end

	local ok, resolved = pcall(player.profile, player)

	if ok and type(resolved) == "table" then
		mask_profile_name(resolved)
	end
end

local function install_nameplate_hooks()
	local hooked_any = false

	for i = 1, #NAMEPLATE_TEMPLATE_PATHS do
		local path = NAMEPLATE_TEMPLATE_PATHS[i]

		local ok = pcall(function ()
			mod:hook_require(path, function (template)
				if type(template) ~= "table" or type(template.update_function) ~= "function" then
					return
				end

				if hooked_nameplate_templates[template] then
					return
				end

				hooked_nameplate_templates[template] = true

				mod:hook(template, "update_function", function (func, parent, ui_renderer, widget, marker, template_arg, dt, t)
					-- 先换数据，再让 vanilla 自己写 widget —— 这样它写出来的就是化名，
					-- widget.dirty 也只由它按需置一次，不会闪烁。
					pcall(mask_marker_profile, marker)

					return func(parent, ui_renderer, widget, marker, template_arg, dt, t)
				end)
			end)

			hooked_any = true
		end)

		if not ok then
			mod:warning("[anon_names] nameplate hook failed for %s", path)
		end
	end

	return hooked_any
end

-- 预热「我的全部角色」集合。
-- 界面（尤其主菜单 / 角色选择）会在**一帧之内**连续查询我的所有角色，而
-- fetch_all_profiles() 是异步的 —— 等第一次查询再惰性触发根本来不及：那一帧全部落进
-- 保守回退，自己的角色被换成池名，而且界面渲染完就缓存住了，之后也不会再查一次。
-- 这里改成进入游戏世界后主动轮询，game_world_ready() 一成立就拉，远早于用户打开界面。
local last_warmup_second = -1
local warmup_disabled = false

local function warmup_my_characters()
	if warmup_disabled or my_characters_loaded then
		return
	end

	local now = os.time and os.time() or nil

	-- 每秒最多试一次；refresh_my_characters 内部还有 10 秒节流 + game_world_ready 守卫
	if now and now == last_warmup_second then
		return
	end

	last_warmup_second = now or last_warmup_second
	refresh_my_characters()
end

mod.update = function (self, dt)
	local ok, err = pcall(warmup_my_characters)

	if not ok then
		-- 预热只是锦上添花：一旦出任何错就永久关掉，绝不拖累游戏
		warmup_disabled = true
		mod:warning("[anon_names] warmup disabled after error: %s", tostring(err))
	end
end

-- ##########################################################
-- ################## 中文字体 fallback #####################
-- 为什么需要：游戏 zh-cn 的字体定义里 `machine_medium` 指向**单个** `noto_sans_sc_black`，
-- 而那是「游戏本地化文本用字」的子集 —— 比 GB2312 一级字库小得多。
-- 2026-10-12 截图实证：池子里的「五角**枫**」显示成「五角▯」，同屏的「五角」「云杉」却正常；
-- 「枫」是一级字（GB2312 23 区），所以旧结论「一级字必然有字形」是错的，池子不能靠删字解决。
--
-- 但游戏**自带四套 CJK 字体**（sc / tc / jp / kr），繁中的定义本身就已经用了 fallback 链
--（ui_fonts_definitions.lua：zh-tw 的 sans_serif = { noto_sans_tc_bold, noto_sans_sc_bold }）。
-- 所以只要把每个字体名都叠成四套链即可 —— **不需要内置任何字体文件**。
--
-- 做法：hook `Managers.font._setup_font_definitions`，**在参数上**补链。
-- 这样无论官方初始化、还是别的字体 mod（例如 show_cjk_glyphs —— 它只补了 sans_serif / serif，
-- 漏掉 machine_medium）来设置，最终生效的都带链，互不冲突；我们再主动应用一次当前定义。

local CJK_LANGS = { "sc", "tc", "jp", "kr" }

local function build_cjk_chain(value, weight)
	local chain = {}
	local seen = {}

	local function push(name)
		if type(name) == "string" and name ~= "" and not seen[name] then
			seen[name] = true
			chain[#chain + 1] = name
		end
	end

	if type(value) == "table" then
		for i = 1, #value do
			push(value[i])
		end
	else
		push(value)
	end

	for i = 1, #CJK_LANGS do
		push("noto_sans_" .. CJK_LANGS[i] .. "_" .. weight)
	end

	return chain
end

local cjk_font_types_cache

local function cjk_font_types()
	if cjk_font_types_cache then
		return cjk_font_types_cache
	end

	local ok, definitions = pcall(function ()
		return mod:original_require("scripts/managers/ui/ui_fonts_definitions")
	end)

	if not ok or type(definitions) ~= "table" then
		cjk_font_types_cache = { sans_serif = "sans_serif", serif = "serif" }

		return cjk_font_types_cache
	end

	local types = definitions.FontTypes or {}

	cjk_font_types_cache = {
		sans_serif = types.sans_serif or "sans_serif",
		serif = types.serif or "serif",
		definitions = definitions,
	}

	return cjk_font_types_cache
end

-- 就地补链（只认 string / table，别的原样留着）
local function patch_font_definitions(font)
	if type(font) ~= "table" then
		return font
	end

	local types = cjk_font_types()

	local function patch(key, weight)
		local value = font[key]

		if type(value) == "table" or type(value) == "string" then
			font[key] = build_cjk_chain(value, weight)
		end
	end

	patch("machine_medium", "black")
	patch(types.sans_serif, "bold")
	patch(types.serif, "black")

	return font
end

-- 加载游戏自带的四个 CJK 字体包（游戏自己的包管理器是幂等的）
local function load_cjk_font_packages()
	local package_manager = Managers.package

	if not package_manager or type(package_manager.load) ~= "function" then
		return
	end

	local packages = {
		"packages/ui/fonts/slug_zh_cn",
		"packages/ui/fonts/slug_zh_tw",
		"packages/ui/fonts/slug_ja",
		"packages/ui/fonts/slug_ko",
	}

	for i = 1, #packages do
		pcall(function ()
			package_manager:load(packages[i], "anon_names", nil, true)
		end)
	end
end

-- 主动把「当前语言的定义」重设一次 —— hook 只保证**之后**被设置的定义带链
local function apply_cjk_font()
	local font_manager = Managers.font

	if not font_manager or type(font_manager._setup_font_definitions) ~= "function" then
		return false
	end

	local types = cjk_font_types()
	local definitions = types.definitions

	if type(definitions) ~= "table" then
		return false
	end

	local locale = Managers.localization and Managers.localization:language() or "zh-cn"
	local locale_fonts = (definitions.locale_specific_fonts or {})[locale] or {}

	local font = patch_font_definitions({
		machine_medium = locale_fonts.machine_medium,
		[types.sans_serif] = locale_fonts[types.sans_serif],
		[types.serif] = locale_fonts[types.serif],
	})

	local ok = pcall(function ()
		font_manager:_setup_font_definitions(font)
	end)

	if not ok then
		return false
	end

	mod._cjk_font_applied = true

	return true
end

local function install_cjk_font(force)
	if mod._cjk_font_installed and not force then
		return true
	end

	if mod:get("cjk_font_fallback") == false then
		return false
	end

	load_cjk_font_packages()

	local font_manager = Managers.font

	if not font_manager or type(font_manager._setup_font_definitions) ~= "function" then
		return false
	end

	if not mod._cjk_font_hooked then
		local ok = pcall(function ()
			mod:hook(font_manager, "_setup_font_definitions", function (func, self, font)
				return func(self, patch_font_definitions(font))
			end)
		end)

		if not ok then
			mod:warning("[anon_names] cjk font hook failed")

			return false
		end

		mod._cjk_font_hooked = true
	end

	mod._cjk_font_installed = true

	if apply_cjk_font() then
		mod:info("[anon_names] cjk font fallback applied (machine_medium / sans_serif / serif)")
	end

	return true
end

mod.on_all_mods_loaded = function (self)
	-- 注意：**不要**在这里预热「我的角色」集合 —— on_all_mods_loaded 发生在游戏世界就绪之前，
	-- 那时 fetch_all_profiles() 会因 master data 未就绪报 BackendError（弹错误 + 游戏进 error state），
	-- 而且它一失败集合就建不起来 → 判据退化 → 放行真名。
	-- refresh_my_characters() 内部有 game_world_ready() 守卫，进入世界后由 mod.update 主动轮询。

	-- 预热 cid→account_id 映射：只读 presence / players，安全
	pcall(refresh_character_accounts)

	-- 头顶名牌：vanilla 直接读 profile.name（真名），绕过全部钩子
	pcall(install_nameplate_hooks)

	-- 中文字体 fallback：修「一级字也变方块」（游戏字体子集 = 本地化文本用字）
	pcall(install_cjk_font)

	-- 补 AnonPlayers 没覆盖的账号名出口（presence account_name）
	pcall(install_account_name_hooks)

	local ok, hooked = pcall(install_hook)

	if ok and hooked then
		return
	end

	mod:warning("[anon_names] AnonPlayers not found or not hookable; aliases stay inactive")
end

mod.on_setting_changed = function (self, setting_id)
	if setting_id == "cjk_font_fallback" then
		if mod:get("cjk_font_fallback") == false then
			mod:info("[anon_names] cjk font fallback disabled (需重进界面/重启才完全生效)")

			return
		end

		pcall(install_cjk_font, true)
	end
end

-- ##########################################################
-- ################## 诊断后门 ##############################
-- 收口之后判据只剩一条规则，但「这个人为什么被判成别人」还得能查。
-- 这些入口只在排查时用，正常流程一次都不经过。
-- 游戏里用 dt-cli 调（get_mod 拿到本 mod）：
--     nn.debug_state()            -- 状态快照：集合 / 映射 / 身份 / 缓存 / hook
--     nn.debug_explain(profile)   -- 对某个 profile 复算判定，列出每一步
--     nn.debug_alias(key)         -- 这个 key 会拿到什么化名
--     nn.debug_trace(true)        -- 开判定追踪（默认关，环形 300 条）
--     nn.debug_trace_dump()       -- 读追踪
--     nn.debug_refresh()          -- 强制重拉「我的角色」集合 + cid→账号映射
--     nn.debug_set(k, v)          -- 改设置并立即生效（等价于界面里改）

local function count_keys(tbl)
	local n = 0

	for _ in pairs(tbl) do
		n = n + 1
	end

	return n
end

trace_record = function (profile, state, masked)
	if not trace_enabled then
		return
	end

	local buffer = trace_buffer
	buffer.n = buffer.n + 1
	buffer[((buffer.n - 1) % 300) + 1] = string.format("cid=%s acc=%s state=%s masked=%s",
		type(profile) == "table" and tostring(profile.character_id) or "nil",
		type(profile) == "table" and tostring(profile.account_id) or "nil",
		tostring(state), tostring(masked))
end

mod.debug_state = function ()
	local identity = local_identity()

	return {
		style = mod:get("mask_style"),
		bot_handling = mod:get("bot_handling"),
		hooked = mod._hooked == true,
		account_name_hooked = mod._account_hooked == true,
		my_characters_loaded = my_characters_loaded,
		my_character_count = count_keys(my_character_ids),
		account_map_count = count_keys(character_accounts),
		alias_cache_count = alias_cache_count,
		my_account_id = identity.account_id,
		my_character_id = type(identity.profile) == "table" and identity.profile.character_id or nil,
		trace_enabled = trace_enabled,
	}
end

mod.debug_explain = function (profile)
	local identity = local_identity()
	local is_table = type(profile) == "table"
	local character_id = is_table and profile.character_id or nil
	local account_id = is_table and profile.account_id or nil
	local state = local_profile_state(profile)

	local steps = {
		"profile 引用         = " .. tostring(profile),
		"本机 profile 引用    = " .. tostring(identity.profile),
		"引用相同?            = " .. tostring(identity.profile == profile),
		"profile.character_id = " .. tostring(character_id),
		"本机 character_id    = " .. tostring(type(identity.profile) == "table" and identity.profile.character_id or nil),
		"「我的角色」集合      = " .. count_keys(my_character_ids) .. " 项 (loaded=" .. tostring(my_characters_loaded) .. ")",
		"cid 在集合里?         = " .. tostring(type(character_id) == "string" and my_character_ids[character_id] == true),
		"profile.account_id   = " .. tostring(account_id),
		"本机 account_id      = " .. tostring(identity.account_id),
		"是机器人?            = " .. tostring(bot_key(profile) ~= nil),
	}

	return {
		state = state,
		verdict = state == true and "我 → 放行真名" or (state == false and "别人 → 换化名" or "判定不了 → 不介入"),
		steps = steps,
	}
end

mod.debug_alias = function (key, style)
	local pool = POOLS[style or mod:get("mask_style")]

	if not pool or type(key) ~= "string" or key == "" then
		return nil
	end

	return pool[(hash_string(key) % #pool) + 1]
end

mod.debug_trace = function (enable)
	trace_enabled = enable == true

	if not trace_enabled then
		trace_buffer = { n = 0 }
	end

	return trace_enabled
end

mod.debug_trace_dump = function ()
	local out = {}
	local buffer = trace_buffer

	for i = 1, math.min(buffer.n, 300) do
		if buffer[i] then
			out[#out + 1] = buffer[i]
		end
	end

	return out
end

mod.debug_refresh = function ()
	my_characters_loaded = false
	characters_logged = false
	account_map_logged = false
	last_character_refresh = -math.huge
	last_account_map_refresh = -math.huge
	warmup_disabled = false

	pcall(refresh_my_characters)
	pcall(refresh_character_accounts)

	return mod.debug_state()
end

mod.debug_set = function (key, value)
	if key ~= "mask_style" and key ~= "bot_handling" then
		return false
	end

	mod:set(key, value, true)

	return mod:get(key)
end

-- 单次判定开销的实测入口（hot path 每次名字查询都走 rewrite_mask）：
--     nn.debug_bench()        -- 默认 20000 次
--     nn.debug_bench(100000)
-- 用一个"别人"的 profile 走完整路径 —— 我自己的 profile 会在 local_profile_state
-- 那一步就 return real_name，测不到底下的 alias_key / alias_for。
mod.debug_bench = function (iterations)
	iterations = tonumber(iterations) or 20000

	local profile = { character_id = "bench-0000-0000-0000-000000000000" }
	local pool = POOLS[mod:get("mask_style")] or POOLS.jieqi
	local t0 = os.clock()

	for _ = 1, iterations do
		mod.rewrite_mask(profile, "BENCH_NAME", nil, "???")
	end

	local dt = os.clock() - t0

	return {
		iterations = iterations,
		pool_size = #pool,
		total_seconds = dt,
		per_call_us = dt / iterations * 1e6,
		calls_per_second = iterations / math.max(dt, 1e-9),
	}
end
