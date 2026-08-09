-- [[ ExBoss Metadata ]]
-- 此文件由打包脚本自动生成或修改，用于控制版本号。
-- 请勿手动通过 Git 提交修改此文件中的版本号，除非你是为了测试。

ExBoss_MetaData = {
    version = "v26.7.13.2130",
    changelog = {
        title = "v26.7.11.2036 更新日志",
        publishedAt = "2026-07-11 20:36",
        fontSize = 14,
        content = [[
@H1@ v26.7.11.2036

@CN@ @H2@ 饰品监控
@CN@ - 新增%s:1302265触发 (智能切换) 需要手动选择
@CN@ - 新增饰品触发时音效 结束时音效 需手动选择音效

@CN@ @H2@ 更新计划
@CN@ - 正式服如没有太重大问题则不会继续更新
@CN@ - EXBOSS会支援第二赛季 并且会比现在做的更好
@CN@ - PTR版本预计在7月下旬推出 我们正在进行大幅度重构

@CN@ @H2@ 代码抄袭
@CN@ - 近期我们注意到有插件抄袭打断监控相关代码 由于开发进度繁忙
@CN@ 我不愿意花时间去吵架 但是我相信这种行为会被很多用户看在眼里
@CN@ 如果你觉得我的代码好用 请至少在插件上标注代码出处或是代码参考!

@EN@ @H2@ Trinket Tracking
@EN@ - Added %s:1302265 trigger (Smart Switch), requires manual selection
@EN@ - Added start/end sound for trinket triggers, requires manual sound selection
@EN@ @H2@ Update Plans
@EN@ - No further updates planned for the live version unless something major comes up
@EN@ - EXBoss will support Season 2, and it'll be even better than what we have now
@EN@ - PTR is expected in late July — we're in the middle of a major rework
@EN@ @H2@ Code Plagiarism
@EN@ - We've recently noticed another addon copying our interrupt-tracking code. We're busy with development and don't want to spend time arguing about it, but we believe this kind of behavior doesn't go unnoticed by users. If you find our code useful, please at least credit the source or reference it in your addon!

@H1@ v26.7.1.1526

@CN@ @H2@ 小怪CD图标
@CN@ - 新增EllesUI姓名版锚点 解决了缩放情况下没有锚定的问题
@CN@ - 优化姓名版图标锚点性能 现在改为登陆后缓存一次 锚点目标在每个姓名版首次出现时缓存 后续零性能消耗

@CN@ @H2@ PTR
@CN@ - 本日PTR更新后暴雪大幅度重构了光环的API 当前版本在PTR建议先行关闭 我们需要大约一天左右时间更新
@CN@ - 后续PTR更新 请在Curse上选择Alpha版本更新 避免冲突

@EN@ @H2@ TrashCD Icons

@EN@ - Added EllesmereUI nameplate anchor support, fixing icon misalignment when nameplate scales
@EN@ - Optimized nameplate icon anchor performance: addon detection now cached once on login, anchor target cached on first appearance of each nameplate with zero overhead thereafter

@EN@ @H2@ PTR

@EN@ - Blizzard significantly reworked the Aura API in today's PTR update. We recommend disabling the addon on PTR for now — an update will be available within approximately one day.
@EN@ - For future PTR updates, please switch to the Alpha channel on CurseForge to avoid conflicts.

@H1@ v26.6.30.1828

@CN@ @H2@ 调度器
@CN@ - 因插件逐渐呈熟 删减了一些重复复查确认的代码来降低性能消耗
@CN@ - 优化了首领战开始时的性能

@CN@ @H2@ 饰品监控
@CN@ - 优化性能

@CN@ @H2@ 字体
@CN@ - 修复了拉丁语系客户端（如德语/法语/西班牙语）中 ä、ö、ü、ß 等字符显示为方块的问题

@CN@ @H2@ 性能优化
@CN@ - 优化了一些反馈性能问题的玩家

@EN@ @H2@ Scheduler
@EN@ - Removed some redundant double-check logic as the plugin has matured, reducing overhead
@EN@ - Improved performance at the start of boss encounters

@EN@ @H2@ Trinket Monitor
@EN@ - Performance optimization

@EN@ @H2@ Fonts
@EN@ - Fixed an issue where characters such as ä, ö, ü, and ß were displayed as square boxes on Latin-script clients (e.g. German, French, Spanish)

@EN@ @H2@ Performance
@EN@ - Addressed performance issues reported by players

@H1@ v26.6.29.1618

@CN@ @H2@ %i:1753
@CN@ - %e:2068 修复了 %s:1268598 在转阶段后偶尔不生效的问题

@CN@ @H2@ GRID引擎
@CN@ - 新增了自定义区域封装 该封装只负责渲染区域大小 内容逻辑由模块自行管理

@CN@ @H2@ 12.1版本
@CN@ - 我们预计未来两天内完成12.1版本的架构 到时候会有详细的下载安装方式说明

@CN@ @H2@ MDI
@CN@ - 虽然我们很想F*Bld 但是不想让玩家受到影响 总之我们会在12.1上线时 以12.1的API架构尽量的支援S1赛季的大秘境
@CN@ (12.1的API改动会倒置当前很多推理的方式失效 我们非常不理解暴雪为何如此愚蠢的在S2赛季 使用12.1的API举办S1副本的MDI比赛
@CN@ 这使得插件作者要为非常少数的几个玩家做"一次性"的适配 并且极度增加了"插件影响比赛"的因素 Fu* Blizz*)

@EN@ @H2@ %i:1753
@EN@ - %e:2068 Fixed an issue where %s:1268598 occasionally failed to trigger after phase transition

@EN@ @H2@ GRID Engine
@EN@ - Added a custom widget host — the host only manages the render area boundaries; content logic is handled independently by each module

@EN@ @H2@ 12.1 Version
@EN@ - We expect to complete the 12.1 architecture within the next two days, with detailed download and installation instructions to follow

@EN@ @H2@ MDI
@EN@ - While we really want to F*Bli *za?d, we don't want players to suffer for it. We will do our best to support Season 1 Mythic+ dungeons using the 12.1 API architecture once 12.1 launches.
@EN@ (The 12.1 API changes will break many of our current inference methods. We strongly disagree with Blizzard's decision to run the S1 MDI tournament using 12.1 APIs during what is technically Season 2 — forcing addon authors into "one-time" compatibility work for a handful of players, while dramatically increasing the risk of addon interference in competitive play. Fu* Blizz*)

@H1@ v26.6.26.0403

@CN@ - 修复PTR客户端下 特定场景可能触发的Lua栈溢出 导致客户端崩溃的问题
@CN@ - 框架被点名改为事件重建队伍框体缓存 高频施法路径仅消费缓存
@CN@ 此改动修复了PTR客户端下 玩家框体递归fallback查找 可能触发Lua栈溢出并导致客户端崩溃的问题。

@EN@ - Fixed an issue on the PTR client where certain scenarios could trigger a Lua stack overflow and cause the client to crash.
@EN@ - Reworked SpellTarget to rebuild party unit frame caches in an event-driven way, with high-frequency cast handling reading from cache only.
@EN@ This change fixes a PTR client issue where recursive fallback lookup of the player's unit frame could trigger a Lua stack overflow and crash the client.

@H1@ v26.6.24.0136

@CN@ @H2@ 队伍框架
@CN@ - 重做队伍框架逻辑 现在以及以后所有涉及队伍框架方光或是显示任何东西的的 统一走中央封装的文件
@CN@ - 现已支援 Blizzard.ElvUI.NDui.EllesUI.Cell.Grid2.DandersFrame.VuhDo.EQOL

@CN@ @H2@ 被点名提示
@CN@ - 我们对被点名提示相关功能进行了较大规模的底层重构。现在无论是 BOSS/小怪被点名提示、小工具(未过滤)被点名提示，
@CN@ 还是框架上显示被点名目标，都统一接入同一套状态管理系统。

@CN@ - 这次重构主要统一了Lua层面的回调分发流程，在保留原有业务过滤逻辑的前提下，减少了大量重复 API 查询，整体运行时开销明显下降。

@CN@ - 这次改动后，准确率也有明显提升。但由于作者目前缺少足够完整的实战测试环境，仍然非常需要反馈。

@CN@ - 特别是某些怪物不会在施法开始后立刻切换目标，而是会延迟 0.3 - 0.6 秒左右才切换到真正目标。这类情况仍然可能影响被点名提示的准确性。
@CN@ 我们非常需要在您遇到这种情况时,主动回报问题来协助我们调试更精准的状态.

@CN@ @H2@ 开发计划
@CN@ - 原则上 这是这个版本最后一个大型重构的项目 为了不影响大家体验 后续时间只会针对小BUG进行修改
@CN@ - 我们会在12.1版本大幅度的重构某些项目和模块 并减少性能消耗

@EN@ @H2@ Party Frames
@EN@ - Reworked the party frame logic. From now on, anything related to party frame highlights or displaying elements on party frames will use one unified central wrapper file.
@EN@ - Currently supported: Blizzard, ElvUI, NDui, EllesUI, Cell, Grid2, DandersFrame, VuhDo, EQOL

@EN@ @H2@ Target Alerts
@EN@ - We have done a major backend rework of the target alert system. Whether it is Boss/Trash target alerts, the unfiltered utility target alert, or target markers shown on party frames, they now all use the same unified state management system.

@EN@ - This rework mainly unifies the Lua-side callback dispatch flow. While preserving the original filtering logic, it also reduces a large amount of duplicated API querying, resulting in noticeably lower runtime overhead.

@EN@ - Accuracy has also improved significantly after this update. However, because the author does not currently have access to a sufficiently complete testing environment, feedback is still extremely important.

@EN@ - In particular, some enemies do not switch to their real target immediately when casting begins, and may instead delay the target swap by around 0.3 - 0.6 seconds. Situations like this can still affect the accuracy of target alerts.
@EN@ - If you encounter cases like this, we would greatly appreciate it if you actively report them to help us debug and improve the system further.

@EN@ @H2@ Development Plans
@EN@ - In principle, this is the last major refactor for this version. To avoid disrupting the user experience, future updates in this cycle will mainly focus on fixing smaller bugs.
@EN@ - In version 12.1, we plan to significantly refactor certain systems and modules again, while also further reducing performance overhead.

@H1@ v26.6.22.0153

@CN@ @H2@ 饰品监控
@CN@ - 支援主属性药水 (三种药水会根据你使用的智能切换进入CD)
@CN@ - 修复了切换饰品时没有刷新问题

@CN@ @H2@ 被点名提示(小工具)
@CN@ - 修复了不显示的问题

@CN@ @H2@ 开发计划
@CN@ - 版本末期为了不影响大家使用 基本遵循着只修复BUG 不大新增/重构的方向

@CN@ @H2@ 公告
@CN@ - 仓库新增了12.1分支 正常PR请提交到主分支 并且注明是否CP(cherry-pick)到12.1 (本地化文件会默认同步)
@CN@ - 出于某些东西可能在我们的跨版本重构计划中 并非所有合并的PR都会同意CP(即使注明)

@EN@ @H2@ Trinket Tracker
@EN@ - Added support for primary stat potions. The tracker will automatically switch to the correct cooldown based on which of the three potions you use.
@EN@ - Fixed an issue where changing trinkets did not refresh the display.

@EN@ @H2@ Target Alert (Tools)
@EN@ - Fixed an issue where it was not displaying.

@EN@ @H2@ Development Plan
@EN@ - As we are in the late stage of the current version cycle, the general direction is to focus on bug fixes and avoid major new features or large refactors so as not to disrupt normal use.

@EN@ @H2@ Announcement
@EN@ - A new 12.1 branch has been added to the repository. Normal PRs should be submitted to the main branch, and the PR description should state whether the change should be CP'd (cherry-picked) to 12.1. Localization files will be synced by default.
@EN@ - Because some changes may conflict with our cross-version refactor plan, not every merged PR will be approved for CP to 12.1, even if it is explicitly requested.

@H1@ v26.6.20.0316

@CN@ %i:1592
@CN@ - %e:3159 私人光环语音现在能正确播放(预设关闭 请自行设置音效)

@EN@ %i:1592
@EN@ - %e:3159 Private Aura voice alerts now play correctly. (Presets are disabled; please configure the sound yourself.)

@H1@ v26.6.19.1946

@CN@ @H2@ 公告
@CN@ - 请在小地图EXBOSS右键点击编辑模式(或是打开设置面板右上的) 确保大多数模块在正确的位置
@CN@ - 为了大多用户使用体验 除非遇到明显影响使用问题 否则大多数的GUI会等到12.1才做调整

@CN@ @H2@ 饰品监控
@CN@ - 彻底修复了重复时间文本问题

@CN@ @H2@ 中央文本
@CN@ - 现在能够正确的显示

@CN@ @H2@ %i:1592 (BETA)
@CN@ - %e:3159 (现在能够正常自定义改名 中央文本提醒等)
@CN@ - 请注意 这是我们首次对于团本BOSS做出测试 该功能还在测试中
@EN@ @H2@ Announcement
@EN@ - Please right-click the EXBOSS minimap icon and enter Edit Mode (or use the button at the top right of the settings panel) to make sure most modules are positioned correctly.
@EN@ - For the overall user experience, unless there is an obvious issue that affects usability, most GUI adjustments will be postponed until 12.1.

@EN@ @H2@ Trinket Monitor
@EN@ - Completely fixed the duplicate timer text issue.

@EN@ @H2@ Central Text
@EN@ - It now displays correctly.

@EN@ @H2@ %i:1592 (BETA)
@EN@ - %e:3159 (custom renaming, central text alerts, and related features now work properly)
@EN@ - Please note: this is our first time testing support for a raid boss, and this feature is still under testing.

@H1@ v26.6.19.0332

@CN@ @H2@ 饰品监控
@CN@ - 修复增长方向问题
@CN@ - 新增居中增长
@CN@ - 修复了有重复时间文本的问题

@CN@ @H2@ 打断监控
@CN@ - 现在退出编辑模式后能正确的隐藏
@EN@ @H2@ Trinket Monitor
@EN@ - Fixed growth direction issues
@EN@ - Added center growth
@EN@ - Fixed the duplicate timer text issue

@EN@ @H2@ Interrupt Tracker
@EN@ - It now hides correctly after exiting edit mode

@H1@ v26.6.18.1648

@CN@ @H2@ 锚点功能(BETA)
@CN@ - 大多数项目的设置页面都加上了锚点功能(私人光环除外)

@CN@ @H2@ 饰品监控
@CN@ - 饰品时间文本支持修改

@CN@ @H2@ %i:1592
@CN@ - %e:3159 补上私人光环(预设尚未设置)

@CN@ @H2@ 小怪内置CD
@CN@ - 针对了一些可能误报的技能做修复 并且一些之前禁用语音的法术重新开放
@CN@ - %i:2811 %s:1282050 %s:1282055
@CN@ - %i:2874 %s:1271623
@CN@ - %i:2915 %s:1257701 %s:1281657

@CN@ @H2@ 小怪 被点名提示
@CN@ - 新增以下法术
@CN@ - %s:1252062 %s:1271623 %s:1253446

@CN@ @H2@ 小地图按钮
@CN@ - 现在可以被隐藏

@EN@ @H2@ Anchor Feature (BETA)
@EN@ - Anchor support has been added to the settings pages of most modules (except Private Aura)

@EN@ @H2@ Trinket Monitor
@EN@ - The trinket timer text is now customizable

@EN@ @H2@ %i:1592
@EN@ - %e:3159 Added Private Aura support (preset not configured yet)

@EN@ @H2@ Built-in Trash Mob Cooldowns
@EN@ - Fixed some spells that could cause false alerts, and re-enabled voice alerts for some spells that had previously been disabled
@EN@ - %i:2811 %s:1282050 %s:1282055
@EN@ - %i:2874 %s:1271623
@EN@ - %i:2915 %s:1257701 %s:1281657

@EN@ @H2@ Trash Mob Targeted Alert
@EN@ - Added the following spells
@EN@ - %s:1252062 %s:1271623 %s:1253446

@EN@ @H2@ Minimap Button
@EN@ - Now can hide

@H1@ v26.6.17.2201

@CN@ @H2@ GitHub
@CN@ - 重新整理并整合了EXBOSS的所有内容(包含本地化文件) 在全新的公开仓库
@CN@ - 现在所有EXBOSS内容均在全新的公开仓库 : https://github.com/Ex-wind/EXBOSS
@CN@ - 我们将会在这几天陆续补上完整地开发手册.MD 开发标准.MD
@CN@ - PR是公开的 欢迎所有人
@CN@ - 我们预计晚些时候(解决一些技术问题后) 变更许可协议
@CN@ - 如果你愿意提供本地化协助 但是不会使用GITHUB 也可以在其他渠道联络我

@CN@ @H2@ WAGO
@CN@ - 我们非常感谢 @Nnoggie 和 @unhalted 的协助
@CN@ - EXBOSS现已支援WAGO更新器 以及你可以再WAGO网站上找到字符串的分享 (由于刚开通 数量较少= =!)
@CN@ - https://wago.io/search/imports/wow/exboss

@CN@ @H2@ 小怪内置CD图标
@CN@ - 修复了非Plater,Platynator下 报错的问题

@CN@ @H2@ %i:2805
@CN@ - %s:1270618 修复了偶尔语音不播报问题

@CN@ @H2@ 小怪内置CD
@CN@ - 我们会在近期陆续按副本更新一些法术 提高整体的准确率

@EN@ @H2@ GitHub
@EN@ - We reorganized and consolidated all EXBOSS content, including localization files, into a brand-new public repository.
@EN@ - All EXBOSS content is now available in the new public repository: https://github.com/Ex-wind/EXBOSS
@EN@ - Over the next few days, we will gradually add the full Development Manual.md and Development Standards.md.
@EN@ - PRs are public, and everyone is welcome.
@EN@ - We expect to change the license later, after resolving some technical issues.
@EN@ - If you would like to help with localization but do not know how to use GitHub, you can also contact me through other channels.

@EN@ @H2@ WAGO
@EN@ - We sincerely thank @Nnoggie and @unhalted for their assistance.
@EN@ - EXBOSS now supports the WAGO updater, and you can also find string exports shared on the WAGO website. Since this was just enabled, there are not many yet.
@EN@ - https://wago.io/search/imports/wow/exboss

@EN@ @H2@ Trash Mob Built-in CD Icons
@EN@ - Fixed an error that occurred when not using Plater or Platynator.

@EN@ @H2@ %i:2805
@EN@ - %s:1270618 Fixed an issue where the voice alert would occasionally not play.

@EN@ @H2@ Trash Mob Built-in CDs
@EN@ - We will continue updating spells by dungeon over the coming days to improve overall accuracy.

@H1@ v26.6.16.0254

@CN@ @H2@ %i:1753
@CN@ - %e:2066 点名预警现在支援 EllesmereUI

@EN@ @H2@ %i:1753
@EN@ - %e:2066 PartyFrame Glow now support EllesmereUI

@H1@ v26.6.15.2306

@CN@ @H2@ 关于PlaterColor(简繁) 插件的公告

@CN@ - 现在插件载入时会检测你是否启用了Platecolor(简繁)的姓名版插件
@CN@ - 如果你启用了该姓名版插件 又同时启用了EXBOSS的小怪内置CD(姓名版)图标时
@CN@ EXBoss会自动将该图标的锚点从姓名版血条切换为姓名版 (UnitFrame)
@CN@ - 这样做是为了避开将锚点锚定到施法条引发的秘密值报错。
@CN@ - 所有使用 PlateColor(简繁) 的用户 需要重新设置小怪内置CD的长宽和锚点

[EN_0] Notice About the PlateColor AddOn
- The addon will now check on load whether you have the PlateColor nameplate addon enabled.
- If PlateColor is enabled and you are also using EXBoss trash built-in CD nameplate icons, EXBoss will automatically switch the icon anchor from the nameplate health bar to the nameplate UnitFrame.
- This is done to avoid secret value errors caused by anchoring to elements indirectly tied to the cast bar.
- All users of PlateColor need to re-adjust the width, height, and anchor position of the trash built-in CD display.

@H1@ v26.6.15.2004

@CN@ @H2@ 重要公告
@CN@ - 这几天会高强度更新，请务必确保您的插件始终处于最新版本
@CN@ - EXBOSS 不受 12.0.7 插件改动影响，无论您身处哪个国家或地区，请随时更新至最新版本

@CN@ @H2@ 被点名提示
@CN@ - 我们已定位到部分被点名提示误报的原因：服务器事件与 API 状态的偶发性更新延迟
@CN@ - 目前已加入 0.1 秒延迟查询，但仍存在极少数误报情况，下次更新计划引入复查机制以进一步改善

@CN@ @H2@ 推理引擎
@CN@ - 升级了推理引擎：部分法术现在能够在读条开始后约 0.1 秒完成识别并立即播放语音提示，无需等待读条结束
@CN@ - 此前需要经历一次完整施法周期才能识别的技能，现在在首次读条开始 0.1 秒内即可识别并正常播报
@CN@ - 新功能上线初期可能存在个别问题，感谢理解，我们会持续跟进并第一时间推送修复

@CN@ @H2@ %i:1209
@CN@ - 大多数技能现在支持在首次读条开始时即推理识别并播放语音（作者暂无条件实机测试，如有打本的朋友遇到问题请帮忙反馈，感谢）
@CN@ - %s:1258174 现在正确支持被点名提示

@CN@ @H2@ 打断监控
@CN@ - 修复了引导法术的判断逻辑错误，现在可正确区分两种情况
@CN@ - 移除了冗余的兼容性判断逻辑
@CN@ - 理论上本版本打断监控准确率为 100%，除非施法实际未被成功打断

@CN@ @H2@ 稳定性
@CN@ - 修复了在特定情况下施法开始事件可能触发内部错误的问题

@EN@ @H2@ Important Notice
@EN@ - We will be pushing frequent updates over the next few days — please make sure your addon is always up to date
@EN@ - EXBOSS is not affected by the 12.0.7 addon changes. Regardless of your region, please update to the latest version at any time

@EN@ @H2@ Target Alerts
@EN@ - We have identified the root cause of occasional false positives in target alerts: sporadic server event timing and API state update delays
@EN@ - A 0.1-second delayed query has already been added, but rare false positives may still occur. A re-validation mechanism is planned for the next update to further improve accuracy

@EN@ @H2@ Inference Engine
@EN@ - Upgraded the inference engine: certain spells can now be identified within ~0.1 seconds of cast start and will immediately trigger voice alerts — no need to wait for the cast to finish
@EN@ - Spells that previously required one full cast cycle to be identified can now be recognized and announced within 0.1 seconds of the first cast beginning
@EN@ - There may be occasional edge cases with the new system. We appreciate your patience and will push fixes as quickly as possible

@EN@ @H2@ %i:1209
@EN@ - Most abilities now support identification and voice playback from the very start of the first cast (the author currently has limited time for live testing — if you run this dungeon after the update, please let us know if you notice any issues, thank you)
@EN@ - %s:1258174 now correctly supports target alerts

@EN@ @H2@ Interrupt Tracking
@EN@ - Fixed a logic error in channel spell completion detection that incorrectly classified natural completions as interrupts (and vice versa)
@EN@ - Removed redundant legacy compatibility checks
@EN@ - Interrupt tracking accuracy is now theoretically 100%, barring cases where the interrupt itself did not land

@EN@ @H2@ Stability
@EN@ - Fixed an internal error that could occur in certain scenarios when a spellcast start event was received

@H1@ v26.6.13.2209

@CN@ @H2@ 语音提示
@CN@ - %i:2915 %e:3328 %s:1257509 现在能正常播放语音

@CN@ @H2@ 被点名提示
@CN@ - %i:2874 %e:3214 %s:1252676 修正了时间 现在会更准确提示

@CN@ @H2@ 饰品监控
@CN@ - 加入了 %s:1260633

@EN@ @H2@ Voice Alerts
@EN@ - %i:2915 %e:3328 %s:1257509 now plays voice alerts correctly

@EN@ @H2@ Target Alert
@EN@ - %i:2874 %e:3214 %s:1252676 timing has been corrected and will now alert more accurately

@EN@ @H2@ Trinket Tracking
@EN@ - Added %s:1260633

@H1@ v26.6.13.1840

@CN@ @H2@ 小怪内置CD

@CN@ - %i:2805的 %s:471643 %s:471648 现在能够正常设置并且播放语音
@CN@ - 请注意 由于该技能没有一个充足的条件去推理 所以我们透过比较复杂的方式实现
@CN@ 目前已经将准确率提高到90%以上 正常战斗情况下 只要避免他冲出去太远 CD 90%就是正常的
@CN@ 正常循环是 冲锋-AOE-冲锋-冲锋-AOE-冲锋 (怪物死亡)
@CN@ 第四次的技能90%是AOE不是冲锋(插件有10%概率会误报)

@CN@ - 新增小怪内置CD技能CD就绪时 图标边框颜色功能(感谢Vovolu 提供的PR)

@CN@ - 修复了多段CD时 计数器错误的序列索引问题

@CN@ @H2@ 被点名提示
@CN@ - 现在默认不会对坦克玩家生效(除非坦克主动勾选)
@CN@ - 新增 %i:2874 %e:3214 %s:1252676
@CN@ - 新增 %i:658 %e:2000 %s:1262745
@CN@ - 新增 %i:2874 %e:3212 %s:1260643

@CN@ @H2@ Pull Request
@CN@ - 由于一些历史原因 仓库目前是私人仓库 如果你愿意提供PR 可以私聊我
@CN@ - 我们将在12.1之前将仓库整合并且公开

@EN@ @H2@ Trash Built-in CDs

@EN@ - The %i:2805 abilities %s:471643 and %s:471648 can now be configured and will play voice alerts correctly.
@EN@ - Please note: because this ability does not provide enough conditions for reliable inference, we implemented it in a relatively complex way.
@EN@ Accuracy has now been improved to over 90%. In normal combat, as long as it does not charge too far away, the CD tracking is correct about 90% of the time.
@EN@ The normal sequence is: Charge -> AOE -> Charge -> Charge -> AOE -> Charge -> (enemy dies)
@EN@ The fourth cast is AOE 90% of the time rather than Charge. (The addon still has about a 10% chance to misreport it.)

@EN@ - Added icon border color support when a trash built-in CD becomes ready. (Thanks to Vovolu for the PR.)

@EN@ - Fixed an incorrect sequence index issue in the counter when handling multi-step CDs.

@EN@ @H2@ Target Alert
@EN@ - It now does not apply to tank players by default, unless the tank explicitly enables it.
@EN@ - Added %i:2874 %e:3214 %s:1252676
@EN@ - Added %i:658 %e:2000 %s:1262745
@EN@ - Added %i:2874 %e:3212 %s:1260643

@EN@ @H2@ Pull Request
@EN@ - Due to some historical reasons, the repository is currently private. If you are willing to submit a PR, you can message me privately.
@EN@ - We will consolidate and make the repository public before 12.1.

@H1@ v26.6.12.2217

@CN@ @H2@ 已知问题
@CN@ - 打断提示现在不提示引导条打断 将在下次更新修复

@CN@ @H2@ GRID引擎
@CN@ - 为BOSS和小怪页面加入了异步渲染功能

@CN@ @H2@ 被点名提示
@CN@ - 现在能在批量设置页面分别批量设置BOSS和小怪的被点名提示
@CN@ - 修复了某些法术不生效的问题 (如还有问题请持续回报)

@CN@ @H2@ BOSS设置面板
@CN@ - 语音现在能够被正常勾选

@CN@ @H2@ 被点名提示
@CN@ - 加入了%i:2874 %e:3212 %s:1260643
@CN@ (更多的会在稍后陆续加入)

@EN@ @H2@ Known Issues
@EN@ - Interrupt alerts currently do not trigger for channeled spell interrupts — will be fixed in the next update

@EN@ @H2@ GRID Engine
@EN@ - Added async rendering for Boss and Trash pages

@EN@ @H2@ Target Alert
@EN@ - Boss and Trash target alerts can now be configured in bulk separately from the Batch Settings page
@EN@ - Fixed an issue where certain spells were not taking effect (please continue to report if the issue persists)

@EN@ @H2@ Boss Settings Panel
@EN@ - Voice checkboxes can now be toggled correctly

@EN@ @H2@ Target Alert
@EN@ - Added %i:2874 %e:3212 %s:1260643
@EN@ (More spells will be added in upcoming updates)

@H1@ v26.6.11.2332

@CN@ @H2@ WAGO支持
@CN@ - EXBOSS现已和WAGO完成对接 插件/配置作者以及用户可以利用WAGO插件包功能导入!

@CN@ @H2@ 调度器
@CN@ - 修复了当没有勾选施法语音时 被点名提示不生效的问题

@CN@ @H2@ BOSS/小怪 - 被点名提示
@CN@ - 修复了一些导致不工作的问题

@CN@ @H2@ 小工具 - 被点名提示
@CN@ - 新增了隐藏91级怪物的选项

@CN@ @H2@ 小怪护盾条
@CN@ - %i:2874 的小怪护盾条 现在可以在设置-副本额外功能关闭

@EN@ @H2@ Wago Integration
@EN@ - EXBoss is now integrated with Wago. Addon/profile authors and users can import via Wago addon packs!

@EN@ @H2@ Scheduler
@EN@ - Fixed an issue where Target Alerts would not trigger when Cast Start Voice was disabled.

@EN@ @H2@ Boss/Trash - Target Alert
@EN@ - Fixed several issues that caused Target Alerts to not work.

@EN@ @H2@ Gadgets - Target Alert
@EN@ - Added an option to hide level 91 mobs.

@EN@ @H2@ Trash Shield Bar
@EN@ - The trash shield bar for %i:2874 can now be disabled in Settings → Dungeon Extra.

@H1@ v26.6.10.2213

@CN@ @H2@ 被点名提示
@CN@ - 大幅度提高了小怪被点名提示的准确率
@CN@ - 修复了小怪的 文本/隐遁提示不生效问提
@CN@ (更新后 所有之前设置的隐遁/文本勾选框需要重新勾上)
@CN@ - 现在 在支持被点名提示的法术卡片右侧有一个红色的图标提示

@CN@ @H2@ 新配置
@CN@ - 增加了新配置切换提示
@CN@ - 强烈建议所有人都切换到新配置来获得更好的体验
@CN@ - 如果你没收到新配置提示的话 可以在语音/配置页面 大米方案最底下点击导入

@CN@ @H2@ 开怪倒数
@CN@ - 现在可以在设置页面关闭

@CN@ @H2@ 小工具 - 被点名提示
@CN@ - 新增 "图标样式"

@CN@ @H2@ 小工具 - 大米怪物施法
@CN@ - 新增隐藏 91级怪物施法选项
@CN@ - 新增在指定首领战中隐藏的选项 请输入首领战ID 用 , 分开 比如(1234,5678,6666)
@CN@ - 可以在BOSS页面左侧的BOSS卡片查询首领战ID
@CN@ - 修复了在某些情况下目标名子错误的问题

@CN@ @H2@ API支持
@CN@ - 现在可以透过ExwidCore的事件分发系统 获得EXBOSS首领/小怪的调度器事件广播
@CN@ (该功能需要约两三天左右的测试)
@CN@ - 使用 ExwindTools:RegisterEvent("事件名", "你的插件名", 回调函数) 来注册
@CN@ 详细文档请看 https://github.com/Ex-wind/EXBOSS-Locale/blob/main/PublicAPI_EN.md

@CN@ @H2@ 正在开发
@CN@ - 正在制作详细的使用手册说明(网页版本)

@EN@ @H2@ Targeted Alert
@EN@ - Significantly improved the accuracy of trash mob targeted alerts.
@EN@ - Fixed an issue where the Text / Stealth alert toggles had no effect on trash mobs.
@EN@ (After this update, all previously configured Stealth/Text checkboxes need to be re-enabled.)
@EN@ - Spell cards that support targeted alerts now show a red icon indicator on the right side.

@EN@ @H2@ New Configuration
@EN@ - Added a new configuration switch prompt.
@EN@ - Everyone is strongly encouraged to switch to the new configuration for a better experience.
@EN@ - If you did not receive the new configuration prompt, go to the Voice/Config page and click Import at the bottom of the Mythic+ section.

@EN@ @H2@ Pull Countdown
@EN@ - Can now be disabled from the settings page.

@EN@ @H2@ Tools — Targeted Alert
@EN@ - Added "Icon Style" option.

@EN@ @H2@ Tools — Mythic+ Mob Cast Bar
@EN@ - Added an option to hide level 91 mob casts.
@EN@ - Added an option to hide the cast bar during specific boss encounters — enter boss encounter IDs separated by commas, e.g. (1234,5678,6666).
@EN@ - Boss encounter IDs can be found on the boss cards on the left side of the Boss page.
@EN@ - Fixed an issue where the target name could display incorrectly in some situations.

@EN@ @H2@ API Support
@EN@ - You can now receive EXBOSS boss/trash scheduler event broadcasts through ExwindCore's event dispatch system.
@EN@ (This feature requires approximately 2–3 days of testing.)
@EN@ - Use ExwindTools:RegisterEvent("EventName", "YourAddonName", callback) to register.
@EN@ Full documentation: https://github.com/Ex-wind/EXBOSS-Locale/blob/main/PublicAPI_EN.md

@EN@ @H2@ In Development
@EN@ - Detailed usage documentation (web version) is currently in production.

@H1@ v26.6.8.2150

@CN@ @H2@ 新功能! 打断监控
@CN@ - 加入打断监控功能 预设关闭 如果需要可以在小工具开启

@CN@ - 此监控准确率100% 但是有两个限制
@CN@ 1.只有打断成功才能监控到
@CN@ 2.所有技能CD都是15秒 并且无法修改
@CN@ 3.玩家本人不受以上两点限制

@CN@ @H2@ BOSS/小怪 被点名提示
@CN@ - %i:2526 %e:2562 %S:386173 现在支持被点名提示 强烈建议开始图标+圆环

@CN@ @H2@ 私人光环
@CN@ - 现在可以移除边框 由于私人光环最终是由暴雪渲染 所以预览模式仅供参考
@CN@ 如果你需要设置的非常详细 建议到 普通模式的 %i:658 %e:1999 boss来测试 他的第一个技能就会施加私人光环

@CN@ - 再次强调 大秘境只有部份的BOSS有私人光环 小怪是完全没有的

@CN@ @H2@ 更新预告
@CN@ - 请注意 我们将会在明天的更新后 提示所有人切换新版本配置 (如果你已经调整过可以跳过)
@CN@ - 如果你当前还在使用没有调整的预设配置 强烈建议切换 会有非常好的使用体验
@CN@ - 接下来的时间将会在优化配置 以及网页教学上面!

@EN@ @H2@ New Feature! Interrupt Tracker
@EN@ - Added the Interrupt Tracker feature. It is disabled by default. If you want to use it, you can enable it under Tools.

@EN@ - This tracker is 100% accurate, but it has two limitations:
@EN@ - It only works when an interrupt is successful.
@EN@ - All skill cooldowns are fixed at 15 seconds and cannot be changed.
@EN@ - The player character is not subject to the two limitations above.

@EN@ @H2@ BOSS/Trash Targeted Alert
@EN@ - %i:2526 %e:2562 %S:386173 now supports targeted alerts. We strongly recommend enabling both the start icon and the ring.

@EN@ @H2@ Private Auras
@EN@ - Borders can now be removed. Since Private Auras are ultimately rendered by Blizzard, Preview Mode is for reference only.
@EN@ If you need very precise setup, we recommend testing in normal mode on the %i:658 %e:1999 boss. Its first ability applies a Private Aura.

@EN@ - To reiterate: in Mythic+, only some bosses have Private Auras. Trash mobs do not have them at all.

@EN@ @H2@ Upcoming Update
@EN@ - Please note: after tomorrow's update, we will prompt everyone to switch to the new version config. (If you have already adjusted yours, you can skip it.)
@EN@ - If you are still using the unadjusted preset config, we strongly recommend switching. The experience will be much better.
@EN@ - Our next focus will be optimizing configs and improving the web guides!

@CN@ @H1@ v26.6.7.1056

@CN@ @H2@ BOSS/小怪 被点名提示
@CN@ - 我们发现了一些BUG 因此重置了BOSS/小怪页面的 被点名提示的 文本 和 隐遁提示 的勾选框
@CN@ - 如果你之前设置过 需要重新勾选

@CN@ @H2@ 小怪内置CD

@CN@ - 重做了 %n:196671的内置CD推理模式 现在改成利用State的Transition Time是否在施法窗口内做比较
@CN@ 如果 %s:388942 %s:388976(如果仍有误报 请持续回报)

@CN@ - 解决了 %n:232146 的 %s:1216459会误报AOE的问题(如果仍遇到错误 请持续回报)

@CN@ @H2@ 编辑模式
@CN@ - 修复了部份模块右键路由错误的问题
@CN@ - 现在所有EXBOSS显示的东西 都可以在编辑模式内拖动调整 并且右键点击会跳转到对应的设置页面
@CN@ - 再次提醒 所有显示的内容因该在编辑模式下拖动到正确的位置 编辑模式勾选框只是方便在编辑模式下预览 不代表是否启用/禁用

@CN@ @H2@ WAGO支持
@CN@ - 插件已经在WAGO上架 并且长期持续更新
@CN@ - WAGO的UI插件包测试已经完成 需要1-3天左右的时间接入

@EN@ @H2@ Boss/Trash Targeted Alert
@EN@ - We found some bugs, so we reset the Text and Stealth Alert checkboxes for the Boss/Trash Targeted Alert pages.
@EN@ - If you had configured them before, you need to check them again.

@EN@ @H2@ Trash Built-in CDs

@EN@ - Reworked the built-in CD inference for %n:196671. It now compares whether the State Transition Time falls within the cast window.
@EN@ - If %s:388942 %s:388976 still produces false positives, please keep reporting them.

@EN@ - Fixed an issue where %s:1216459 from %n:232146 could falsely report as an AOE. If you still encounter errors, please keep reporting them.

@EN@ @H2@ Edit Mode
@EN@ - Fixed incorrect right-click routing for some modules.
@EN@ - All EXBOSS display elements can now be moved in Edit Mode, and right-clicking them will jump to the corresponding settings page.
@EN@ - Reminder: all display elements should be moved to the correct position in Edit Mode. The Edit Mode checkboxes are only for preview convenience and do not indicate whether a feature is enabled or disabled.

@EN@ @H2@ WAGO Support
@EN@ - The addon is now available on WAGO and will continue to receive long-term updates.
@EN@ - Testing for the WAGO UI addon pack has been completed, and integration is expected within about 1-3 days.

@H1@ v26.6.7.0124

@CN@ @H2@ 新功能(小工具)
@CN@ - 新增了饰品监控模块 预设了主流饰品和药水 默认禁用 (正常只需要启用调整位置就可以)

@CN@ @H2@ 问题修复
@CN@ - %i:2805 %e:3056 %s:466556 现在支持被点名提示功能 (非常建议开启)

@CN@ @H2@ 开发进度
@CN@ - 预计明天/后天加入打断监控
@CN@ - 我们正在加快测试被点名提示功能 会在约两天后大幅度更新默认配置

@EN@ @H2@ New Features (Utilities)
@EN@ - Added a Trinket Monitor module with presets for popular trinkets and potions; disabled by default (simply enable it and adjust the position as needed)

@EN@ @H2@ Bug Fixes
@EN@ - %i:2805 %e:3056 %s:466556 now supports the "You Are Targeted" alert (highly recommended to enable)

@EN@ @H2@ Development Progress
@EN@ - Interrupt monitor is planned for tomorrow or the day after
@EN@ - We are accelerating testing of the "You Are Targeted" alert; default configurations will receive a major update in approximately two days

@H1@ v26.6.5.1823
@CN@ @H2@ WAGO支持
@CN@ - 我们已经与WA团队对接 完成WAGO的API相关代码 预计这几天完成所有的接入

@CN@ @H2@ 问题修复
@CN@ - 紧急修复了LSM使用暴雪原生材质时 边框渲染异常的问题
@CN@ - 修复了GRID引擎在渲染EXBOSS窗口时 如果打开ExwindTools会丢失的问题

@CN@ @H2@ 使用说明
@CN@ - 目前大多功能已经开发完成 本赛季剩余时间只会陆续修复一些问题
@CN@ - 会在接下来两天做一个全面的插件使用介绍说明

@EN@ @H2@ WAGO Integration
@EN@ - The WAGO integration API is now complete. Full WAGO integration is expected to be finished over the next few days.

@EN@ @H2@ Fixes
@EN@ - Urgently fixed a border rendering issue when LSM used Blizzard native border textures.

@EN@ @H2@ Usage Notes
@EN@ - Most features are now largely complete. For the rest of this season, updates will mainly focus on fixing remaining issues.
@EN@ - A full plugin usage guide will be added over the next two days.

@H1@ v26.6.1.1244

@H2@ 请加频道提供最即时的协助 / Join Our Channels for Fastest Support

- 中文用户请加QQ群:2168036546
- 英文用户请加DC: discord.gg/6fwVhRHyg9
- Chinese users: join QQ Group 2168036546
- English users: join Discord discord.gg/6fwVhRHyg9

- 请在这两个地方反馈或是提问 任何问题除了睡觉时间都会很快得到回复
- 请尽量不要在其他渠道提问
- Please report issues or ask questions in these two channels — responses are fast except during sleep hours.
- Please avoid asking in other channels.

@H2@ 开发中 / In Development
- 正在重新制作一些GUI中 为不同的语言提供更好的体验
- Reworking parts of the GUI to provide a better experience for different languages.
- 即将上线非常强大的点名提示功能
- A powerful targeted-player alert system is coming soon.
- 下次更新后 我们会分离更新日志语言 提供更好的观看体验
- Starting from the next update, the changelog will be split by language for better readability.

@H2@ 配置保存 / Config Save
- 修复了当异步情况下可能导致的保存配置污染问题
- Fixed an issue where async operations could corrupt saved configuration data.

@H2@ 通用 / General
- 修复了英文客户端未完整本地化的问题
- Fixed missing localization entries for English clients.

@H2@ 圆环系统 / Ring System
- 新增了圆环背景选择
- Added background selection option for the ring display.

@H2@ 施法进度条 / Cast Progress Bar
- 修复了锚点合上下增长时锚定错误的问题 现在会正确的按照锚点去生长
- Fixed incorrect anchor behavior when the bar grows upward or downward — it now correctly follows the anchor point.

@H2@ 错误修复 / Bug Fixes
- 修正了施法进度条会与小怪额外护盾条设置冲突的问题
- Fixed a conflict between the cast progress bar settings and the trash mob extra shield bar settings.
- (PS:此改动可能需要大多数玩家重新设置额外护盾条)

@H1@ v26.5.24.1035

@H2@ 支援服务 (Support)
- 新增DC频道:discord.gg/ZV75Db4CT (可以在首页复制)
- Added a Discord channel: discord.gg/ZV75Db4CT (link can be copied from the homepage)
- 该频道陆续完善中
- The channel is being gradually built up.

@H2@ 通用 (General)
- 重新启用 迈萨拉洞窟 (Maisara Caverns)小怪护盾提示 并且修复了(并测试了)性能问题
- Re-enabled trash mob shield alerts for Maisara Caverns and fixed (and tested) the associated performance issue.
- 重新补全并检查所有EXBOSS的编辑模式 现在所有编辑模式因该都能正确的移动 修改
- Fully reviewed and restored all EXBoss Edit Mode elements. All Edit Mode frames should now move and resize correctly.
- 暂时禁止了LSM字体下拉选单的样式渲染 改成普通字体 以解决在特定语言客户端下污染框架池的问题
- Temporarily disabled styled rendering in the LSM font dropdown. It now uses plain text to prevent frame pool corruption on certain language clients.
- 新增 周围怪物施法 提示(从ExwindTools迁移过来) 默认关闭 如果需要在设置-工具 开启
- Added a Nearby Mob Cast alert (migrated from ExwindTools). Disabled by default; enable it under Settings > Tools.
- 补齐了大多数缺失的英语翻译 (如果有遗漏请回报)
- Filled in most missing English translations. If anything is still missing, please report it.
- 新增节点(NPX) 自动对话
- Added auto-gossip support for Nexus-Point Xenas (NPX).
- 修复了倒数-播放文本时 "54321"无法播放问题
- Fixed an issue where "54321" could not play when the countdown "Play Text" option was enabled.

@H2@ 配置分享 (Configuration Sharing)
- 整套系统已经完成 目前在做上线前的最后测试 预计明天最慢后天发布
- The full system is complete and currently undergoing final pre-release testing. Expected to release tomorrow, or the day after at the latest.

@H2@ 本地化 (Localization)
- 预设情况下小怪技能提示因该会正确的显示英文
- Trash mob skill alerts should now correctly display in English by default.
- 新增(临时的)英文语音包 (如果没有自动切换的话 请在语音那边手动切换ENG语音包)
- Added a temporary English voice pack. It should switch automatically; if not, manually select the ENG voice pack in the voice settings.
- 正常情况下 英文客户端因该能够正常显示英文文本+英文语音
- On English clients, text and voice alerts should now display and play correctly in English under normal conditions.

@H2@ 执政团之座 (Seat of the Triumvirate)
- 修复了 鲁拉(LURA)的 %1268598 的时间轴问题
- Fixed a timeline issue with L'ura's %1268598.
- 请注意 该技能由于暴雪设计问题 有三种不同的随机时间轴 理论上我们已经修复 但是只打过一次 并未有大量的测试数据验证
我们非常需要这个的测试反馈 如果你愿意协助的话 不管测试完成后正常/不正常 都请告知我们(透过DC或是QQ)
- Note: due to a Blizzard design quirk, this ability has three different randomized timelines. We believe it is fixed, but it has only been tested once and lacks extensive validation data. We would greatly appreciate test feedback — whether it works correctly or not, please let us know via Discord or QQ.

@H1@ v26.5.21.2010

@H2@ 新功能 (New Features)
- 新增迈萨拉洞窟 爆炸小怪护盾条提示 请在编辑模式调整位置 相关设置在设置-副本额外功能里面调整
- Added a shield bar alert for explosive trash mobs in Maisara Caverns. Position can be adjusted in Edit Mode. Related settings are under Settings > Dungeon Extra Features.

- 单独分离迈萨拉洞窟 2号BOSS的护盾条 请在编辑模式调整位置
- The shield bar for Boss 2 (Vordaza) in Maisara Caverns has been separated as its own element. Position can be adjusted in Edit Mode.

- 新增被点名提示 默认禁用 如果需要请在设置页面开启(只有DPS和治疗能开启)
- Added a Targeted Alert feature. Disabled by default; enable it in the Settings page if needed. (Only available for DPS and Healer roles.)

@H2@ 音效
- 加入一些预设音效 并且我们正在收集一些实用的音效(主要用于首领战中的提示)
- Added several preset sound effects, and we are currently collecting more practical sounds (mainly for boss fight alerts).

- 如果您手上有好的音效资源(且没有版权问题) 愿意贡献 欢迎联系我
- If you have good sound resources and they are free of copyright issues, contributions are welcome. Feel free to contact me.

@H2@ 本地化
- 全自动本地化流程仍有一些问题 我们正在做最后的修复与对接 预计周末前会一切正常
- The fully automated localization workflow still has some issues. We are working on the final fixes and integration, and expect everything to be stable before the weekend.

@H1@ v26.5.20.0121

@H2@ 公告 (Announcement)
- 作者生病了,停止更新一天 后天继续恢复高强度更新
- The author is sick and will pause updates for one day. High-frequency updates will resume the day after tomorrow.

@H2@ 计时条/施法进度条 (Timer Bar / Cast Progress Bar)
- 修复了锚点与增长方向错误的问题
- Fixed incorrect anchor position and grow direction behavior.

@H2@ 本地化方案 (Localization)
- 再重新通知前 请勿使用任何第三方翻译插件包 我们已经收到不少会导致BUG/配置丢失的问题
- Please do not use any third-party translation addons until further notice. We have received multiple reports of bugs and configuration loss caused by them.
- 本地化可以到:https://github.com/Ex-wind/EXBOSS-Locale 提交 或是通过DC:ex_wind 联络我
- Localization contributions are welcome at: https://github.com/Ex-wind/EXBOSS-Locale — or contact us via Discord: ex_wind

@H1@ v26.5.18.2023

@H2@ 通用 (General)
- 提高了圆环的文本层级
- Raised the text layer priority for the ring display.
- 新增了开怪倒数支持
- Added pull countdown support.

@H2@ 注意! (Notice)
- 目前不建议使用任何的第三方翻译插件 我们已经收到不少BUG 比如丢失配置等问题
- We currently do not recommend using any third-party translation addons. We have received numerous bug reports related to them, such as lost configurations.
- 如果你是第三方插件作者 可以透过Discord联系我(ex_wind) 我将提供详细的新方案给你
- If you are a third-party addon author, feel free to contact me on Discord (ex_wind). I will provide you with a detailed integration plan.
- 所有本地化内容可以到 https://github.com/Ex-wind/EXBOSS-Locale 提交(或是透过discord ex_wind 联络我)
- All localization contributions can be submitted at https://github.com/Ex-wind/EXBOSS-Locale (or contact me directly via Discord: ex_wind).
- 我们正在做最后的适配 最慢48小时内会推出全英文(以及其他部份语言)的技能/语音配置
- We are finishing the final adjustments. A full English (and partial other languages) skill and voice configuration will be released within 48 hours at the latest.

@H1@ v26.5.17.1856

@H2@ 通用(General)
- 修改文件载入顺序 确保本地化方案正确运行
- (Changed addon load order to ensure locale system initializes correctly)
- 修复自动计算边框宽度引发的报错问题
- (Fixed a crash caused by automatic border width calculation)

@H1@ v26.5.16.0134

@H2@ 语音(VOICE)
- 移除了当缺少语音时的Fallback逻辑 (不会在错误的播放54321)
- Removed the fallback logic when voice lines are missing. (It will no longer incorrectly play 54321.)

@H2@ 小怪内置CD(Trash CD)
- 修复了在Platynator插件下图标位置异常的问题
- Fixed an issue where TrashCD nameplate icons could appear in incorrect positions when using Platynator.

@H2@ 更新计划(Update)
- 预计周末完成完整的本地化方案 以及推出新的预设配置 加上英文翻译
- We expect to complete the full localization plan by the weekend, along with new preset configurations and English translations.

@H1@ v26.5.15.0857

@H2@ 通用
- 修复计时条边框问题
- 小怪内置CD 姓名版图标增加了层级选项
- (语音正在大范围重做 预设配置也在大范围重做 预计1-2天)
- (大范围英语本地化正在进行中 请给我们1-2天时间)
@H2@ General
- Fixed the timer bar border issue.
- Added a layering option for TrashCD nameplate icons.
- A large-scale English localization update is currently in progress. Please give us 1-2 days.

@H1@ v26.5.14.0721

@H2@ 学院 (AA) (Algeth'ar Academy)
- 解决2号BOSS后小怪误判的问题
- Fixed an issue where trash mobs could be misidentified after Boss 2.

@H2@ 推理系统 (Inference System)
- 禁用了L2根据首次施法提前锁定NPC导致误判的问题
- Disabled the L2 behavior that could prematurely lock an NPC based on the expected first cast timing and cause misidentification.
- 该问题主要显现于 通天峰
- (This issue was most noticeable in Skyreach.)

@H1@ v26.5.14.0503

@H2@ 通用 (General)
- 添加副本自动对话功能
- Added automatic dungeon gossip functionality.

@H2@ 本地化 (Localization)
- 添加英文语音包 默认会自动切换 如果出现问题可以在配置(第二个标签)手动切换
- Added an English voice pack. It switches automatically by default; if there are any issues, you can manually switch it in the settings (the second tab).

@H2@ 其他 (Other)
- 正在赶工英文的配置 会在两天内发布
- The English configuration is currently being rushed and will be released within two days.

@H2@ 节点(NPX) (Nexus-Point X)
- 修复1号BOSS的 %1257509 施法进度条错误提示的问题
- Fixed the incorrect cast progress bar alert for Boss 1's %1257509.

@H1@ v26.5.13.1931

@H2@ 执政团2号BOSS (Seat 2 Boss)
- 狗跳人提醒:现在发光样式同步设置面板的团队框架发光 可以自行设置样式(颜色暂时改不了)
- Dog Jump Target Alert: The glow style now syncs with the raid frame glow settings panel, allowing you to customize the style yourself (color customization is not available yet).

@H2@ 中央倒数文字BUG修复
- 当调度器使用暴雪原生轴情况下 取消图标边框 以避免触碰到秘密值报错
- Removed icon borders when the scheduler is using the Blizzard default timeline, fixing errors caused by the Blizzard default timeline.

@H2@ 其他(Other)
- 添加了如果开启怪物高亮提示时的警报
- Added a warning when enemy highlight affix are enabled.
- 再次提醒 如果开启了新的大秘境词缀(怪物高亮) 会导致小怪内置CD判断错误 可以在大秘境钥石NPC那边对话关闭
- Reminder: Enabling the new Mythic+ affix (enemy highlight) will cause incorrect built-in mob cooldown tracking. You can disable it by talking to the Mythic+ Keystone NPC.

@H1@ v26.5.13.1633

@H2@ 私人光环(Private Aura)
- 修复了私人光环设置介面问题 (PS:批量修改的私人光环尚未完成 请勿使用! 将在下个更新后完工)
- Fixed the Private Aura settings UI. (PS: batch editing for Private Aura is not finished yet, please do not use it. It will be completed in the next update.)

@H2@ 施法进度条(Cast Progress Bar)
- 增加上下间距调整功能
Added a vertical spacing adjustment option.

- 提高了边框的层级 现在会正确的 文本>边框>条本体
Increased the border layer priority. It now renders correctly as Text > Border > Bar body.

@H2@ 小怪内置CD(姓名版图标) (Trash Built-in CD (Nameplate Icons))
- 重做了锚点逻辑 如果仍有问题请持续回报
- Reworked the anchor logic. If there are still issues, please continue reporting them.

@H2@ 其他 (Other)
- 原先预告更新的功能正在制作中 会在几小时后陆续更新
- The previously announced upcoming features are still in development and will be rolled out gradually over the next few hours.

@H1@ v26.5.12.2252

@H2@ 新增 批量设置 功能 (Added Batch Settings feature)
- 位于设置界面 该功能可以将大量技能批量的修改 来达到快速个性化设置的目的
- Located in the Settings interface, this feature allows batch editing of large numbers of abilities for faster personalization.

@H2@ 本地化 (Localization)
- 将于明天更新英文语音
- (English voice updates will be added tomorrow)
- 预计将在2天内完成全新的配置 并支援全英文配置
- (A fully updated configuration is expected within 2 days, with full English configuration support.)

@H2@ 配置系统
- 已经完成90% 预计三天后包含使用教程一起发布
- (The system is already 90% complete and is expected to be released in 3 days together with a usage guide.)

@H1@ v26.5.9.1953

@H2@ 艾杰斯亚学院 (Algeth'ar Academy)
- 修复了 %388942 语音错误的问题
- Fixed an issue where %388942 played the wrong voice line.

@H2@ 首领施法/引导系统 (Boss Cast / Channel System)

- 为了长远的发展 已重做整套系统 如遇到问题请回报给作者
- For long-term development, the entire boss cast/channel system has been reworked. If you encounter any issues, please report them to the author.

@H2@ 首领警报 (EncounterTimeLine)
- 魔导师平台 Gemellus 吉美尔鲁斯已经支援自定义时间轴
- Magister's Terrace / Gemellus now supports a custom timeline.

- 请注意：该BOSS在 50%转阶段时，暴雪原生计时条会丢失所有事件，EXBOSS的计时条已修复这个问题。
- Note: at the 50% phase transition, Blizzard's native timeline loses all events for this boss. EXBOSS timers have fixed this issue.

@H2@ 开发计划 (Development Plans)
- 请注意! 我们即将在这几天推出全新的配置内容
- Please note! We will be releasing a brand-new set of configurations within the next few days.

@H1@ v26.5.7.1626

@H2@ 小怪语音 (Trash Voice)
- 暂时禁用了 迈萨拉洞窟 Maisara Caverns 空洞的裂魂者的语音功能(CD正常显示)
- Temporarily disabled voice alerts for Hollow Soulrender in Maisara Caverns. (CD timers still display normally)
- 暂时禁用了 破阵铁骑 Phalanx Breaker 的语音提醒 (CD正常显示)
- Temporarily disabled voice alerts for Phalanx Breaker. (CD timers still display normally)
- 暂时禁用了 残存镜像 Lingering Image 的语音提醒 (CD正常显示)
- Temporarily disabled voice alerts for Lingering Image. (CD timers still display normally)

@H2@ 计时条名称 (Timer Bar Names)
- 所有未改名的计时条 现在会正确的显示本地化的名称
- All timer bars without custom renamed text will now correctly display localized names.

@H2@ 本地化修复 (Localization Fixes)
- 感谢所有玩家对插件的支持 由于我们开发之初没有想过会再国际上如此受欢迎
今天会尽快更新 确保至少提供基本的全英文选项
- Thank you all for your support. We did not expect EXBoss to become this popular internationally when development first began.
We will update as soon as possible to ensure that at least a basic full-English option is available.

@H2@ 语音提示 (Voice Alerts)
- 新增TTS语音功能(只有大秘境生效 团本无法生效)
- Added TTS voice support. (Currently only works in Mythic+, not in raids)
- Magister's Terrace 魔导师平台 3号BOSS 暂时不要使用TTS语音
- Please do not use TTS voice for Boss 3 in Magister's Terrace for now.

@H2@ 开发计划 (Development Plans)
- 我们正在开发一套DPS被点名的完整提示
- We are developing a complete alert system for DPS-targeted mechanics.
- 我们正在开发一套完整的配置分享方案 可以直接导出代码打包成插件 请详见后续的详细介绍
- We are developing a complete configuration sharing system that can export settings as code and package them directly into a plugin. More details will be provided later.
- 我们正在开发一套(非常基础)的enUS配置,但仅仅是为了能稍微正常显示
- We are developing a very basic enUS configuration, mainly so the addon can display somewhat properly.
- 在Twitch上有很多主播花上非常多时间精心调试并完整测试整套EXBOSS配置
(包含什么技能因该重点提示 什么技能不需要提示),欢迎项这些主播咨询
- Many Twitch streamers have spent a great deal of time carefully tuning and fully testing their EXBoss configurations
(including which abilities should be prioritized and which do not need alerts). You are welcome to consult those streamers.

@H1@ v26.5.5.1951

@H2@ 施法/圆环提示 (Cast /Ring Fixes)

- 修复了艾杰斯亚学院 多拉苟萨的回响 的 力量真空
- Fixed Power Vacuum from Echo of Doragosa in Algeth'ar Academy

- 修复了通天峰 鲁克兰 的 灼热飞羽
- Fixed Searing Quills from Rukhran in Skyreach

@H2@ 已知问题 (Known Issues)

- 节点 的1号BOSS 核闪引爆 将在下次更新修复
- Corespark Detonation from the first boss in The Nexus (NPX) will be fixed in the next update

@H1@ v26.5.4.1654

@H2@ 新增倒数系统
@H2@ New Countdown System
- 设置页面的倒数页面可以更改音效
- The countdown settings page now lets you change the sound effects.
- 如果你勾了 提前倒数 5秒 然后"没有勾" 播放文字
那就会在技能剩余秒时播放 5.4.3.2.1
- If you enable a 5-second lead countdown and do not enable "Play Text",
it will play 5, 4, 3, 2, 1 at the remaining seconds of the skill.
- 如果你勾了 提前倒数 5秒 然后"勾了" 播放文字
那就会在技能
剩余6秒时 播放你选择的(比如准备范围伤害)
剩余5秒时 播放5 4 3 2 1
- If you enable a 5-second lead countdown and also enable "Play Text",
then at 6 seconds remaining it will play the label you selected
(for example, "Prepare AOE"),
and at 5 seconds remaining it will play 5, 4, 3, 2, 1.

- 如果你看不懂 很简单 把执政团 1号BOSS的 残杀 设置倒数 然后多测试几次你就懂了!
- If that still sounds confusing, just set up a countdown for Decimate on the
first boss of Seat of the Triumvirate and test it a few times. You will understand it quickly.

@H2@ 风行者之塔
@H2@ Windrunner Spire
- 新增幻形秘术师 护盾施法提示
- Added a shield-cast alert for Spellguard Magus.

@H2@ 迈萨拉洞窟
@H2@ Maisara Caverns
- 修复恐怖食魂者 施法误触发语音问题
- Fixed an issue where Dread Souleater could incorrectly trigger voice alerts while casting.
- 妖缚飞鹰 新增内置CD
- Added a built-in cooldown for Hexbound Eagle.
- 2号BOSS 沃达扎 新增 转阶段护盾百分比进度条
(外观样式以及位置 继承 "施法进度条")
- Added a phase-transition shield percentage progress bar for Boss 2, Vordaza.
(Its appearance and position inherit from Cast Progress Bar.)

@H1@ v26.5.3.1404

@H2@ 小怪内置CD Trash CD
- 修复了一个法术有唯一特征时 没有第一时间在L2被推理出来的问题
- Fixed an issue where spells with unique identifying traits were not being inferred immediately at L2.

@H2@ 配置系统 Configuration
- 修复了一个如果使用很老旧配置导入时 很多语音不生效不工作的问题
- Fixed an issue where importing very old configurations could cause many voice alerts to fail or not work at all.
- 建议如果你在很久以前下载EXBOSS 且近期语音很不稳定的话 建议最好还是重置设置 这是一个早期开发遗留问题
- If you downloaded EXBOSS a long time ago and voice alerts have been unstable recently, it is recommended to reset your settings. This is a legacy issue from early development.

@H2@ 怪物施法进度条 Mob Cast Bar
- 如果没有改名的情况下 现在默认使用法术名称
- If no custom rename is set, the cast bar now uses the spell name by default.

@H2@ 圆环系统 Ring System
- 新增时间倒数
- Added time countdown display.
- 新增名称显示
- Added name display.
- 修复了Skyreach通天峰 Rukhran 鲁克兰 圆环不准确问题
- Fixed inaccurate ring timing for Rukhran in Skyreach.

@H1@ v26.5.1.1342

@H2@ 首领时间轴 (Encounter TimeLine)
- 在非中文客户端情况下 如果未自定义名称 现在支援正确的本地化法术名称
- Encounter timelines now use correctly localized spell names on non-Chinese clients when no custom name override is set.

@H2@ 小怪内置CD (Trash CD)
- 修复了偶尔某些怪物进入战斗后无法在L1推理出来的问题
- Fixed an issue where some mobs occasionally could not be inferred at L1 after entering combat.

@H2@ 显示层(Display)
- 修复了BOSS和小怪的圆环/计时条 偶尔不生效问题(如果还有发生请持续回报)
- Fixed an issue where boss/trash rings and timer bars could occasionally fail to appear. Please keep reporting if this still happens.
- 中央五秒倒数文字:新增图标边框和设置选项
- Added icon borders and related settings to the center 5-second countdown text.
- "施法条"现在的文本层级高于边框
- Cast bar text now renders above the border.

@H1@ v26.4.29.2257

@H2@ 使用者界面
- 增加整体面板UI缩放功能 在左上的下拉选单
- Added overall panel UI scaling through the dropdown menu in the top-left corner.

@H2@ 本地化
-基本所有内容支援enUS
- Most content now supports enUS.

@H2@ BOSS技能设置页面
- 修改了UI组件位置 提供更好的适配
- Adjusted the positions of UI components for better layout compatibility.
- 修复了开始施法语音无法延迟播放的问题
- Fixed an issue where cast-start voice alerts could not be delayed properly.
- 修复了非CN客户端下 施法条文字技能文字错误的问题
- Fixed incorrect cast bar skill text on non-CN clients.
- 新增施法条改名
- Added cast bar renaming.

@H2@ 设置页面
- 所有计时条类设置新增计时条图标边框
- Added timer bar icon borders to all timer bar related settings.
- 所有计时条文本层级高于边框
- All timer bar text layers now render above the borders.

@H2@ 小怪内置CD
- 优化怪物进入战斗判定逻辑
- Optimized the logic for detecting when trash mobs enter combat.
- 新增怪物缓存逻辑 此举解决了在丢失姓名版情况下CD重置的问题
- Added mob caching logic, which fixes cooldown resets when nameplates are lost.

@H2@ 问题修复
- 修复了选择LSM音效 没选择语音时 即使不勾选也会播放Fallback语音问题(感谢@KIRA回报)
- Fixed an issue where fallback voice would still play if an LSM source was selected but no voice was chosen, even when the trigger was unchecked. (Thanks to @KIRA for the report.)

@H2@ 当前已知问题

- 风行者之塔的(Windrunner Spire) 破阵铁骑(232122)phalanx-breaker 技能无法准确判定
- In Windrunner Spire, the Phalanx-Breaker (232122) skill still cannot be identified accurately.

- 语音包的首领语音前几天我们大改了逻辑 使其更为精准 但是有少部份技能会不兼容 这点需要手动修正 大概这两天会修复完成
- We significantly reworked the boss voice pack logic a few days ago to improve accuracy, but a small number of skills are currently incompatible. These will need manual fixes and should be resolved within the next couple of days.

@H1@ v26.4.27.0714

@H2@ 公告
- 小怪内置CD从 12.0.5改版后我们一直没有去调整 有不少问题 这几天工作内容主要在修复一些底层逻辑 配置分享
匹配英语客户端 以及解决12.0.5遇到的问题
- 预计明天开始高强度的修复各种小怪CD的问题

@H2@ Notice
- Built-in trash mob cooldowns have not been adjusted since the 12.0.5 update, so there are quite a few issues. Recent work has mainly focused on fixing lower-level logic, configuration sharing, English client compatibility, and issues caused by 12.0.5.
- Starting tomorrow, we expect to focus heavily on fixing various trash mob cooldown issues.

@H2@ 调度器
- 语音播放时机改成当State变更为Finish时播放
- 由于少数技能的State变更判定时机有点奇怪 会陆续人工修正(发布前已经测完5个本)

@H2@ Scheduler
- Voice playback timing has been changed to play when the State changes to Finish.
- A few skills have unusual State change timing, so they will be manually adjusted over time. Five dungeons have already been fully tested before release.

@H2@ 节点希纳斯
- 核技工程长卡斯雷瑟 重写时间轴逻辑 并通过多次测试
(额外补充:目前除了魔导师平台 3号BOSS外 所有BOSS皆实现了时间轴解析)

@H2@ Nexus-Point Xenas
- Reworked the timeline logic for Chief Corewright Kasreth and verified it through multiple tests.
(Additional note: except for the third boss in Magisters' Terrace, timeline parsing is now implemented for all bosses.)

@H2@ 新增计时条功能
- 可在任意技能选择开启读条提示(与圆环效果相同 单纯多一种显示样式)

@H2@ New Timer Bar Feature
- You can now enable cast bar-style timer prompts for any skill. This works the same as the ring display, but provides an additional visual style.

@H1@ v26.4.26.0801

@H2@ 节点
- 核心守卫奈萨拉 和 洛萨克森 以重新支援固定轴模式(可以正常改名)
- 核心守卫奈萨拉 新增易伤提示

@H1@ v26.4.25.2147

@H2@ 导出/导入功能
- 现在所有设置内容都会随着外观方案导出/导入 (需要重新生成代码)

@H2@ Export / Import Feature
- All settings are now exported/imported together with the appearance profile. (Code regeneration required)

@H2@ 更新提示
- 在12.0.5版本后 有三个首领计时器需要改动 (大约这两天完成) 改动完成前会先使用暴雪原生计时器
@ 核心守卫奈萨拉
@ 洛萨克森
@ 吉美尔鲁斯

- 部份小怪技能CD在12.0.5版本后失效/准确率下降 但是都可以解决 会在这两天时间内快速修复
- 鉴于以上情形 请大家尽量频繁更新插件 确保是最新的资料内容

@H2@ Update Notice
- After version 12.0.5, three boss timers need updates. These changes should be completed within the next couple of days. Before they are updated, Blizzard’s default encounter timers will be used instead.
@ Corewarden Nysarra
@ Lothraxion
@ Gemellus

Some trash mob skill cooldowns may become invalid or less accurate after version 12.0.5, but these issues can be fixed and will be addressed quickly within the next couple of days.

Due to the above, please update the addon frequently to make sure you are using the latest data.

@H1@ v26.4.25.0046

@H2@ 小怪读条推理引擎
- 修复一个导致L2推理无法正确处里读条后引导法术的问题

@H2@ Trash Cast Inference Engine
- Fixed an issue where L2 inference could not correctly handle cast-into-channel spells

@H1@ v26.4.24.2202

@H2@ 设置
- 修复导出导入时的错误

@H1@ v26.4.24.1845

@H2@ 本地化
- 大多内容支持enUS 有些UI会挡住字体问题会在晚些时候修复

@H2@ Localization
- Most content now supports enUS. Some UI elements may still have text overlap issues, and those will be fixed later.

@H1@ v26.4.21.1213

@H2@ 调度器
- 修正一个问题 当调度引擎遇到(试验)时间轴State变更为完成时 可能被提前清理而导致语音偶发不播放的问题。

@H2@ Scheduler
- Fixed an issue where, when an experimental timeline state changed to Finished, the event could be cleaned up too early and cause voice alerts to occasionally fail to play.

@H1@ v26.4.20.0013

@H2@ 小怪CD
- 艾杰斯亚学院 Algeth'ar Academy问题大多已修复正常 现在能正确视别假死断条后的事件
- 风行者之塔 Windrunner Spire 大多问题已修复 除了3号BOSS前的破阵铁骑会有问题(暂时没办法解决) 其余均正常
- 修正 通天峰 Skyreach 的太阳元素Solar Elemental 宝珠跟注意躲地板提示相反的问题(如果你之前改过这个设置 需要自己手动改)
- 剩余部份明天将陆续修正完成

@H2@ Trash CD
- Most issues in Algeth'ar Academy have been fixed. Events after Feign Death / interrupted casts should now be detected correctly.
- Most issues in Windrunner Spire have been fixed. The only known remaining issue is the Arrayed Stormrider before the third boss, which cannot be resolved for now. Everything else should work normally.
- Fixed reversed alerts for Solar Elemental in Skyreach: the orb target-swap alert and the ground-dodge alert were assigned incorrectly. If you previously changed this setting manually, you will need to adjust it yourself.
- The remaining parts will be fixed gradually tomorrow.

@H1@ v26.4.18.2127

@H2@ 小怪CD
- 修正了学院的判定逻辑
- 修正了某些隐遁 假死后 怪物语音播放错的逻辑 (可能有个别怪物还需要手动调整)

- 内置CD预计两三天内调试完 再调试完之前遇到任何BUG可以先单独禁用

@H1@ v26.3.30.2054

@H2@ 通用

- 所有大秘境副本首领时间轴均已更新(如果没意外的话所有BOSS都是最准确的)
- 今天开始如有任何BOSS时间轴不准确请第一时间回报
- 目前 以下四个BOSS临时使用暴雪原生轴 (除了无法计时条改名 无法提前5秒显示 其余均正常)
会在后续继续优化
执政团之座 : 鲁拉
节点希纳斯 : 核心守卫奈萨拉
风行者之塔 : 指挥官克罗鲁科
魔导师平台 : 吉美尔鲁斯

- 修复了MDT刷新导致的性能问题 现在性能消耗已大幅降低

- 修复了某些情况下私人光环注册导致报错的问题

@H2@ 开发计划
- 当前暂时先以测试BOSS以及优化提示内容为主
- 下一轮将推出小怪内置CD的测试 但是时间还不确定
- 团队减伤的将在下个月左右安排

@H2@ General

- All Mythic+ dungeon boss timelines have been updated. If nothing unexpected slipped through, every boss timeline should now be at its most accurate state so far.
- Starting today, if any boss timeline is inaccurate, please report it as soon as possible.
- The following four bosses are temporarily using the Blizzard native timeline.
Everything except custom bar renaming and 5-second early display should behave normally.
They will continue to be optimized in a later update.
- Seat of the Triumvirate: L'ura
- Nexus-Point Xenas: Corewarden Nysarra
- Windrunner Spire: Commander Kroluk
- Magister's Terrace: Gemellus
- Fixed an MDT refresh issue that was causing unnecessary performance overhead. MDT performance usage has now been significantly reduced.
- Fixed an issue where private aura registration could trigger errors in some situations.

@H2@ Development Plans

- The current focus is boss testing and continued refinement of alert content.
- The next round will include testing for built-in trash mob cooldowns, but the release timing is not confirmed yet.
- Raid defensive cooldown support is currently planned for around next month.

@H1@ v26.3.26.2201

@H2@ EXBOSS 2.0 公开测试版本 更新内容

@H2@ 重要公告和开发计划
- 本插件尚未开发完成 整体进度还不到50%
并且插件制作时使用的是BETA测试的数据 大秘境才刚开放 作者需要一定的时间来更新
如果你急用 建议使用DBM,BW 不建议使用开发中的版本

- 本周目标先将大多时间轴校准 私人光环补齐(我们收集数据的方法与其他插件不同) 再进行下一步动作

- 团本的开发调试会暂缓 并且我非常不建议开荒团本玩家使用这个插件 因该使用DBM BW

- EXBOSS主要针对中高层大秘境 很多功能都还在开发中没做好 如果你需要开箱上手即用的目前有很多别的插件选择

@H2@ 配置

- 如同上周末预告 由于我们把整套配置系统代码重写了
所以副本配置都已经重置 并且如果没有重大BUG的话 不会再重置副本配置

- 配置作者大约需要几天时间内来完成 到时候预设会有配置作者的配置可选

- 默认配置全部开启并没有过滤(除了DPS职责不显示坦克技能)

@H2@ 通用
- 可以在设置最顶端的通用设置选择是否开启团本/大秘境(由于制作的时候关服了 还没有测试)

@H2@ 新功能 MDT路线
- 在MDT标签页选择配置后导入 然后点击右侧小窗开启

@H2@ 新功能 私人光环
- 有些缺少的会陆续更新 语音还未加入 后面会陆续补上

@H1@ v26.3.23.0722

@H2@ 公告

- 我们在接下来几天内会接入配置系统 会根据你当前的专精自动选择配置
所有提示的配置(比如这个技能治疗要不要监控 语音内容合不合理) 都会有专门的配置作者分享
并且都是长年的称号选手 BETA有过上百场副本经验

目前所有提醒设置全开单纯是为了测试用的! 这并不是最终的情况! !
请大家理解 并且多给予我们一些时间 非常谢谢! ! !

- 一些其他的公告可以关注我B站 会有最及时的开发计划公告

@H1@ v26.3.20.0018

@H2@ 通用
- 修复了勾选框按钮偶尔点击失效的问题

@H2@ 反馈
- 任何团本语音不合理的部份 都欢迎反馈 这几天会陆续更新

@H1@ v26.3.19.1614

@H2@ 默认选项
- 现在默认只启用竖条

@H1@ v26.3.19.1443

@H2@ 性能
- 修复了进入战斗瞬间卡顿问题
经过10次的实测 进入战斗5秒内ExBoss的CPU峰值不超过1ms (U7-265K)

@H2@ 数据
- 为了长远的发展 修改了底层数据保存结构的逻辑
所以之前的副本数据可能会丢失 为此实在抱歉 并且之后因该都会长期正常了

@H2@ 团本
- 初始团本数据来源于B测 不是很完美 这周会陆续的修改优化
(如果你对任何团本的提示有建议 非常欢迎透过B站后台或是NGA留言告知我)
(如果有大量的反馈 也可以私聊我添加联络方式!)

@H1@ v26.3.19.0927

@H2@ 通用

- 新增 EXBoss 独立版本 metadata
- 新增更新日志弹窗系统
- 新增面板底部更新日志按钮
- 新增 EXBoss 独立发布脚本目录
        ]],
    },
}
