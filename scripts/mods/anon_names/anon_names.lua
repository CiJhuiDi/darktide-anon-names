-- chunkname: @scripts/mods/anon_names/anon_names.lua
--[[
	匿名名池 (Anon Names) v1.0.2
	Author: CiJhuiDi

	AnonPlayers 的附属：不改它「谁该被匿名」的决定，只替换「用什么名字」。

	接入点：包住 AnonPlayers 的 mod.anonymize(profile, real_name, is_account)。
	它 8 个 CLASS 钩子全部通过 mod.anonymize(...) 出结果，所以只在这一处拦截即可全覆盖：
		PlayerInfo.character_name / user_display_name（后者被它 hook_origin 独占，不能碰）
		RemotePlayer.name / character_name、HumanPlayer.name、BotPlayer.name
		PresenceEntryMyself / PresenceEntryImmaterium.character_name
		profile_utils.character_name

	判据：func() 返回真名 = AnonPlayers 决定不匿名（掩码模式 0），原样放行；
	      返回别的 = 已被匿名，换成节气／花草化名。

	因此与 AnonPlayers 的 6 个设置项互不干扰，也不依赖加载顺序。
	同一玩家全程同一个化名（按 account_id/character_id 稳定哈希 + 缓存）。
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

-- key 优先级：account_id（跨角色稳定）→ character_id → 真名字符串兜底
-- 账号名与角色名共用同一个 key，保证同一个玩家只有一个化名
local function alias_key(profile, real_name, is_account)
	if type(profile) == "table" then
		local account_id = profile.account_id

		if type(account_id) == "string" and account_id ~= "" then
			return account_id
		end

		local character_id = profile.character_id

		if type(character_id) == "string" and character_id ~= "" then
			return character_id
		end
	end

	if type(real_name) == "string" and real_name ~= "" then
		return (is_account and "acc:" or "name:") .. real_name
	end

	return nil
end

-- 唯一的分配逻辑：哈希取模。不查表、不记录、不重试
local function alias_for(key, pool)
	return pool[(hash_string(key) % #pool) + 1]
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

local function bot_key(profile)
	if not profile then
		return nil
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

	for unique_id, bot in pairs(bots) do
		if bot and bot._profile == profile then
			return "bot:" .. tostring(bot._local_player_id or unique_id)
		end
	end

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

-- 「是不是我」的三态判定：true = 确定是我 / false = 确定不是我 / **nil = 判定不了**。
-- 调用方**只有拿到 false（确证是别人）才允许覆盖上游放行的真名**；nil 必须放行。
--
-- 为什么必须三态（2026-10-09 实测踩到）：本机 profile 的 account_id 是 nil，
-- 而账号名 / presence 路径传进来的 profile 可能**没有 character_id**。
-- 旧实现遇到这种情况返回 false（=「不是我」），于是拿 anon_others = 3 去裁决我自己的名字
-- → **把玩家自己的名字也匿名了**。判定不了就应该什么都不做。
--
-- 判据优先级：
--   1. 引用相同（hub / 任务里 hook 收到的就是同一个 profile 表）
--   2. character_id 相同（跨场景副本；两边的 id 都有效才可判定）
--   3. account_id 相同（本机 HumanPlayer._account_id 与 profile.account_id）
-- 三条都不成立 → nil。
local function local_profile_state(profile)
	if type(profile) ~= "table" then
		return nil
	end

	local player_manager = Managers.player
	local my_profile
	local my_account_id

	if player_manager and type(player_manager.local_player) == "function" then
		local ok, local_player = pcall(function ()
			return player_manager:local_player(1)
		end)

		if ok and local_player then
			my_profile = local_player._profile

			local ok_acc, account_id = pcall(function ()
				return local_player:account_id()
			end)

			if ok_acc then
				my_account_id = account_id
			end
		end
	end

	if type(my_profile) == "table" then
		if my_profile == profile then
			return true
		end

		local mine = my_profile.character_id
		local theirs = profile.character_id

		if type(mine) == "string" and mine ~= "" and type(theirs) == "string" and theirs ~= "" then
			return theirs == mine
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

-- 上游的「他人」设置是否要求匿名。0 = 用户明确要求不匿名他人（含账号名），照抄真名；
-- 其余值（含读不到）按「应当匿名」处理 —— 拿不准时宁可匿名，这是本 mod 的定位。
local function others_masked(is_account)
	local anon_mod = get_mod("AnonPlayers")

	if not anon_mod or type(anon_mod.get) ~= "function" then
		return true
	end

	local ok, value = pcall(function ()
		return anon_mod:get(is_account and "anon_other_accounts" or "anon_others")
	end)

	if not ok then
		return true
	end

	return value ~= 0 and value ~= false
end

-- ##########################################################
-- ################## 掩码改写 ##############################

mod.rewrite_mask = function (profile, real_name, is_account, masked)
	local style = mod:get("mask_style")
	local pool = POOLS[style]

	if not style or style == "off" or not pool then
		return masked
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
	elseif masked == real_name then
		-- 上游返回真名。**只有确证是别人、且上游的他人设置要求匿名时才覆盖**；
		-- 是我、或判定不了（nil）一律放行 —— 绝不能把玩家自己的名字改掉
		if local_profile_state(profile) ~= false or not others_masked(is_account) then
			return masked
		end
	end

	-- 账号名要不要匿名完全由 AnonPlayers 的「其他账户名称 / 你的账户名称」决定，
	-- 本 mod 不再叠加自己的一层开关 —— 它匿名我们就换化名，它放行我们就放行
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

mod.on_all_mods_loaded = function (self)
	local ok, hooked = pcall(install_hook)

	if ok and hooked then
		return
	end

	mod:warning("[anon_names] AnonPlayers not found or not hookable; aliases stay inactive")
end
