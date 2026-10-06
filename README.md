# 匿名名池 (Anon Names) v1.0.0

《战锤 40K：暗潮》DMF mod：**AnonPlayers 的附属** —— 不改它「谁该被匿名」的决定，只把它的掩码（`???` / 随机代码 / 性格名）换成中文意象化名。

适合直播：观众看到的不再是雷同的 `???` 或 `8f0ea` 这种代码，而是一池认得出的中文名字。

## 功能

- **化名风格随时切换**（共 9 个池、484 项）：
  - 二十四节气 24 项（立春 … 大寒）
  - 花草五大类**各自独立可选用**：花木 69 / 草本 51 / 藤蔓 32 / 树木 52 / 园艺花卉 50
  - 全部花草 254 项
  - 中国传统星名 206 项（二十八宿距星、北斗七星、著名亮星、三垣与二十八宿星官、近南极星官）
  - 全部混合 484 项
- **同一玩家全程同名**：按账号 / 角色 ID 做稳定哈希，跨局也是同一个化名
- **机器人可单独设置**：也用化名 / 保持 `???` / 显示游戏原名
- 生效位置：社交面板、聊天、结算、头顶名牌、哀星号队伍面板、邀请组队界面、预任务大厅与角色选择
- 与 [color_mark](https://github.com/CiJhuiDi/darktide-color-mark) 共存：被 `/mark` 的玩家仍优先显示彩色真名

## 依赖

- **DMF**（Darktide Mod Framework）
- **AnonPlayers**（**必需**）—— 本 mod 只替换它的掩码，不自己做「谁该被匿名」的决策

## 安装

1. 把 `anon_names` 文件夹整个复制到游戏 mods 目录：
   `Steam\steamapps\common\Warhammer 40,000 DARKTIDE\mods\`
2. **不需要**改 `mod_load_order.txt`：DML 会加载 mods 目录下所有 mod，而本 mod 与 AnonPlayers 的加载顺序无关（它包的是函数而不是 CLASS 钩子）
3. 启动游戏 → ESC → **Mod Options → 匿名名池** 调整风格
4. ⚠️ 装好后**完全重启游戏**才生效（热重载只部分加载新代码，日志会新旧混）

## 配置项

| 设置 | 默认 | 说明 |
|---|---|---|
| 化名风格 `mask_style` | 二十四节气 | `jieqi` / `flora` / `flower` / `herb` / `vine` / `tree` / `garden` / `star` / `mixed` / `off` |
| 机器人 `bot_handling` | 开（也用化名） | `开` 机器人也用化名 / `关` 保持 AnonPlayers 的 `???` / `显示游戏原名` |
| 账户名也一起改 `apply_to_accounts` | 开 | 仅当 AnonPlayers 也匿名账号名时才有区别（它默认不匿名账号名） |

## 化名池

| 风格 | 值 | 数量 |
|---|---|---|
| 二十四节气 | `jieqi` | 24 |
| 全部花草 | `flora` | 254 |
| 花木 | `flower` | 69 |
| 草本 | `herb` | 51 |
| 藤蔓 | `vine` | 32 |
| 树木 | `tree` | 52 |
| 园艺花卉 | `garden` | 50 |
| 传统星名 | `star` | 206 |
| 全部混合 | `mixed` | 484 |
| 关闭 | `off` | — |

传统星名取自香港太空馆[「中国星区、星官及星名英译表」](https://hk.space.museum/tc/web/spm/resources/teachers-corner/constellations-and-myths/glossary-of-chinese-star-regions-asterisms-and-star-names.html)（基于《仪象考成》体系），已剔除凶名与不雅名（积尸、天屎、屠肆之类）、四象名、单字宿名与生僻字。

## 关于撞名

化名由稳定哈希直接从池子里取，**刻意不做去重**：同队两人有概率拿到同一个化名，池子越小概率越高。这样换来的是零状态设计——不存在「池子耗尽」「集体重排」「局内换名」这些问题。

想少撞名就换大池子，而不是期待去重：

| 池 | 4 人队撞名率 |
|---|---|
| 藤蔓 | ~18% |
| 二十四节气 | ~23% |
| 园艺花卉 / 草本 / 树木 | ~11% |
| 花木 | ~8.5% |
| 传统星名 | ~2.9% |
| 全部花草 | ~2.3% |
| 全部混合 | ~1.2% |

## 已知限制

- **依赖 AnonPlayers**：未安装或版本不可 hook 时本 mod 静默不生效，日志会打印 `[anon_names]` 开头的警告
- 任务中（combat）头顶名字仍由 AnonPlayers 处理，本 mod 跟随它的结果
- `mask_style` 若存着已删除的旧值，按「关闭」处理（不会报错也不会乱改名）
- 池子里有 8 个 4 字名和 1 个 5 字名，极窄的名牌可能显示不全

## 文件结构

```
anon_names/
├── anon_names.mod                          # 入口清单
├── info.json                               # mod 元数据（含 AnonPlayers 依赖声明）
└── scripts/mods/anon_names/
    ├── anon_names.lua                      # 主逻辑（化名池 + 哈希分配 + hook 接入）
    ├── anon_names_data.lua                 # 设置项定义
    └── anon_names_localization.lua         # 中英本地化
```

## 更新日志

- **v1.0.0**（2026-10-06）：首个发布版

## 许可 / License

MIT License —— 详见 [LICENSE](LICENSE)。
