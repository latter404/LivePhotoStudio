# 实况工坊 1.1

2026-11-06 · 内部构建 36

## 本次更新

- 时间轴两端拖动都会预览对应边界；直接封装按选区限制播放范围，减少预览与输出时长不一致。
- 新增 0.25×、0.5×、1×、1.5×、2×、4× 播放速度，预览与输出同步。
- 默认以最终播放时长为准，不超过 3 秒；切换半速时默认选取 1.5 秒原片。用户手动调整过选区长度后保留原片选区，不再自动缩短；「重置为 3 秒」恢复默认行为；默认选区超过当前时间轴范围时自动扩大显示范围。
- 始终显示输出时长。变速使用高质量转码，保持声音音调；HDR 转为 SDR，不做光流补帧。
- GIF 新增采样体积预估及处理后的实际大小。估算采用少量帧，有误差，不保证符合平台大小限制；GIF 时间精度为百分之一秒。
- 「关于」加入可点击的 GitHub 项目链接；修复切换界面语言后外观与语言菜单仍残留旧语言的问题。

## 验证范围

- 108 项自动测试通过，覆盖精确剪切、首尾帧、复制码流、变速、声音、GIF 时长与体积、默认三秒、手动时长、短素材、历史存储、取消及错误恢复。
- 本机已验证 4K / 8K 横竖屏实况、旋转封面与播放方向、变速及完整 3 秒原尺寸 8K GIF。默认时长和菜单更新未改动这轮已验证的编码引擎。
- 实际界面检查了窄窗口、正常与半速默认三秒、手动拖动加长、文件导出及 GitHub 链接；iPhone 已收到带秒表的正常与半速实况，两张文件均为 3.000 秒，用户确认播放正常。
- 未在朋友的 M2 Max、Intel Mac 或 macOS 14 设备上重新实机验证；通用构建和包验证不代替这些设备测试。

处理结果和设置沿用旧版。运行无需额外安装 FFmpeg、Python 或 Homebrew。安装包为 Apple 芯片 / Intel 通用版本，最低 macOS 14；采用 ad-hoc 签名，尚未完成 Developer ID 签名与公证。原尺寸 8K GIF 仍可能消耗较多内存、时间和磁盘空间。

## English

Version **1.1 (36)** adds synchronized trim-edge previews, precise passthrough presentation ranges, 0.25×–4× playback speed, sampled GIF size estimates and actual sizes, and a clickable project link in About. It also fixes stale menu localization after changing languages.

Output defaults to at most **3 seconds**, including slow motion. Before duration customization, speed changes adjust the source selection. Dragging either selection edge opts into a custom duration; subsequent speed changes preserve that source selection. **Reset to 3 s** restores the default. Output duration is always visible.

108 automated tests passed. Local media checks covered landscape/portrait 4K and 8K Live Photos, rotation, speed changes, and a full 3-second original-size 8K GIF. The user confirmed normal iPhone playback of two visible-timecode Live Photos, normal speed and half speed, both measuring 3.000 seconds in their output files. M2 Max, Intel, and macOS 14 hardware acceptance is not claimed. Speed changes re-encode to SDR while preserving audio pitch, without optical-flow interpolation. GIF estimates are approximate. The universal package is ad-hoc signed and is not Developer-ID signed or notarized.

---

# 实况工坊 1.0

2026-11-05。按首次对外正式发布整理为版本 **1.0**，内部构建号继续递增为 33。下方保留之前开发迭代时的编号与验证记录。

- 修复从手动浅色或深色切回“跟随系统”时，标题栏和内容区域不同步的问题；外观统一由 AppKit 管理，SwiftUI 窗口继承，不重复强制窗口配色。
- 关于页面显示简洁版本号 1.0，内部构建号可从版本提示查看。
- 保留现有左右布局、视频编辑、历史结果和本次处理角标逻辑。

## 本轮验证

- 95 项完整自动测试通过，0 失败；新增窗口、SwiftUI 宿主和新建面板的外观继承回归测试。
- 带明确用途标识的测试版现场确认：手动浅色／深色均可切回跟随系统；macOS 深色→浅色→深色时，应用内容与标题栏同步。测试结束恢复原有系统深色设置。
- 同一段已加载的合成 8K MOV 在外观切换中保持载入，0–3 秒选区及左右布局保留；这不是新的 8K 导出验收。
- 正式 1.0（内部构建 33）已安装，与正式构建逐文件一致；关于页面显示 1.0。重新启动显示已选 0／10、无本次处理角标，重新打开先前视频成功。
- 现有处理库 39 个文件哈希与检查前一致；本轮没有新增或删除真实处理结果。

最终 DMG、源码包与已安装应用的一致性由交付校验清单及 QA 包审计记录。本轮没有重新执行媒体导出、照片图库写入或 iPhone 接收测试；也未在另一台 M2 Max、Intel Mac 或旧版 macOS 上实机验证。历史测试不作为本版的新验收。

安装包为通用架构、本地 ad-hoc 签名，尚未完成 Developer ID 签名与公证；其他 Mac 的首次安装仍可能出现系统来源验证提示。

## English

Version **1.0** starts the public release numbering; the internal build counter remains monotonic at 33. Appearance now has one application-level override so SwiftUI windows and native panels inherit together. The previous development records remain below under their original numbers.

---

# 实况工坊 1.11.4（32）

2026-11-05 · 本地交付版本，尚未上传 GitHub

本版只调整「处理」角标的统计含义及对应引导，保持左右布局、历史结果列表和媒体处理流程。

## 改进

- **本次处理数量：** 「处理」右上红色角标统计本次应用运行中新生成且仍可用的结果，不使用历史总数或手动勾选数。0 时隐藏，重启后归零。
- **选择与历史：** 新生成结果仍自动加入当前选择，便于连续制作后批量操作；手动勾选历史结果不改变角标，完整历史继续保留在「已处理」列表。
- **引导入口：** 四步引导的第三步改为聚焦「已处理」入口，首次启动没有角标时也能找到列表。
- **数量说明：** 列表没有固定条数上限，也不按数量自动淘汰结果；未新增保存数量限制或后台清理规则。现有三个自动删除选项默认关闭。

## 本轮验证

已从源码确认：结果载入没有条数上限或按数量淘汰的逻辑，当前逐项读取元数据。此结论不表示磁盘容量无限，也不构成大规模列表性能验收。

| 范围 | 实际结果 |
| --- | --- |
| 自动测试 | 94 项完整测试通过，0 失败。 |
| 构建与安装 | 通用测试版及正式构建成功，正式 1.11.4（32）已安装并与构建逐文件哈希一致。 |
| 启动与布局 | 测试版启动显示 0／9、处理按钮没有角标，截图确认左右布局保留；正式安装版也确认 0／9、无角标、批量操作禁用。 |
| 历史选择 | 打开 9 项历史列表并全选，返回后显示 9／9、批量操作按钮启用，处理角标仍不出现。 |
| 新结果与生命周期 | 新结果计数 1→2、历史选择不增加角标、重启归零，以及清理、迁移由临时目录自动测试验证；本轮没有向真实处理库新增结果。 |
| 使用引导 | 手动查看时仅观察到第 1／4、2／4 步，未现场确认第三步聚焦或完整四步。 |
| 恢复查看素材 | 更新后重新打开先前查看的合成 8K 视频，确认 7680 × 4320、30 fps、0–3 秒选区，处理按钮启用且无角标；这仅是导入／恢复查看，不是 8K 导出验收。 |
| 真实库及正式交付 | 真实处理库 35 个文件的哈希逐一与本轮检查前一致；最终安装包一致性由交付清单及包审计承载。 |

1.11.3 及更早版本记录保留为历史证据，不视为本版新验收结果。本轮没有进行实际投送、导出、添加到照片或 iPhone 接收验证。

## English summary

**LivePhoto Studio 1.11.4 (32)** narrows the red **Process** badge to items created during the current app session that remain available. It hides at zero and resets on relaunch, independently of the historical total or manual selection. Newly processed items still join the current selection, and the complete history remains accessible through **Processed**. Guide step three now highlights that entry, which remains usable when the badge is hidden.

Source inspection found no fixed collection-size cap or count-based eviction; metadata is loaded item by item. No new retention limit or cleanup policy is introduced, and all three automatic-deletion settings remain off by default. This does not establish unlimited capacity or large-collection performance.

All 94 tests passed with zero failures, and the universal test and production builds succeeded. The test build launched with zero of nine items selected, no badge, and the two-column layout intact. Selecting all nine historical items enabled the delivery controls without showing a badge. Temporary-directory tests covered new-item counts from one to two, historical selection not increasing the badge, reset on relaunch, cleanup, and migration; no new item was added to the real collection. Only guide steps one and two were observed; step-three focus and the complete four-step sequence were not confirmed.

The formal 1.11.4 (32) app was installed and matched the production build by per-file hashes. Its launch state showed zero of nine selected, no Process badge, and disabled delivery controls. The previously viewed synthetic 8K video was reopened, showing 7680 × 4320 at 30 fps, a zero-to-three-second selection, and an enabled Process button with no badge. This was an import/viewing check, not 8K export validation. All 35 real collection file hashes matched the pre-check snapshot. Final package identity is recorded in the matching delivery manifest and audit. No actual AirDrop, export, Photos import, or iPhone receipt was performed in this cycle. Prior release records below are historical evidence only.

---

# 实况工坊 1.11.3（31）

2026-11-05 · 本地交付版本，尚未上传 GitHub

本版调整导入提示、颜色层级、启动时的结果选择以及关于信息。保留 1.11.2 的左右布局和原有媒体处理流程。

## 改进

- **导入提示：** `⌘O` 快捷键独立成行，与「或点击选择文件」分开。
- **颜色层级：** 使用系统主次文字颜色和统一的强调色，保持明暗外观下的含义一致。
- **启动选择：** 历史处理结果继续保留，每次启动默认不勾选。本次运行中新生成的结果会加入当前选区，已有选择在本次运行内保留，便于连续制作后批量操作。
- **关于信息：** 关于面板保留名称、版本、应用说明、© 2026 latter404 和「开源许可」入口。MIT、Revive 与 makelive 的详细归属说明移到许可面板顶部，四份完整许可及说明文本继续提供。
- **许可范围：** 对照固定版本的上游文件保留版权与许可；文档明确区分项目代码、上游代码、Apple 平台组件和 AI 图标的来源说明，不将全部材料一概归为项目自有 MIT 代码。

## 本轮验证

| 范围 | 实际结果 |
| --- | --- |
| 自动测试 | 93 项完整测试通过，0 失败。 |
| 构建与正式安装 | 通用测试版及正式构建成功；已安装的正式 1.11.3（31）与正式构建逐文件哈希一致，启动显示 0／9，三个批量动作均禁用。安装包核验以对应版本的交付清单及审计记录为准。 |
| 明暗空态 | 浅色、深色截图均检查了完整左右栏与独立成行的快捷键提示。 |
| 启动选择 | 启动显示 0／9，列表内 9 项复选框均未勾选，批量操作按钮禁用；手动选择 1 项后显示 1／9，按钮启用。退出测试进程后重新启动恢复 0／9。 |
| 导入与颜色 | 导入合成 4K／24 fps 视频，浅色截图检查了主文字、蓝色选中项、时间轴、处理按钮、开启的静音开关及自定义滑条；仅为导入和界面检查，不是 4K 导出验收。 |
| 关于与许可展示 | 正式安装版关于截图确认仅保留名称、版本、简介、© 2026 latter404 与许可按钮。许可面板实际读取到四份完整文本，包含新版第三方声明；顶部简介与项目 MIT 清楚可见，滚动到底可见 makelive 作者和 MIT 原文末尾。 |
| 本轮未执行 | 未实际隔空投送、文件导出或添加到照片，未进行 iPhone 接收与 LIVE 播放验收。 |

已完成的来源核对：Revive 与 makelive 固定参考版本的在线原始 LICENSE，均与随项目保留的许可文件逐字节一致；Revive 的字体例外段落原样保留。此核对不替代对 AI 图标排他版权或商标权利的判断，也不代表其他设备的运行测试。

## English summary

**LivePhoto Studio 1.11.3 (31)** puts the `⌘O` hint on its own line, aligns text and accent colors with system roles, and starts each launch with historical processed items unselected. Newly processed items join the current selection during the same session. About keeps the app identity, version, description, copyright, and license button; detailed attribution moves to the license panel without removing the four complete notices.

The full suite passed 93 tests with zero failures, and the universal test build succeeded. Light and dark empty-state screenshots confirmed the two-column layout and separate keyboard hint. Launch showed zero of nine items selected, all nine collection checkboxes off, and delivery controls disabled. Selecting one item enabled the controls; quitting the test process and relaunching restored zero selection. A synthetic 4K/24 fps source was imported in light appearance to inspect primary text, blue selections, the timeline, Process, the enabled mute switch, and custom sliders. This was an import and UI check, not a 4K export test. No actual AirDrop, export, Photos import, or iPhone receipt was performed in this cycle.

The formal 1.11.3 (31) app was installed and matched the production build by per-file hashes. Its launch state showed zero of nine selected and all three delivery actions disabled. The installed About panel was visually confirmed to retain only the name, version, description, copyright, and license button. All four full notices, including the updated third-party statement, were read from the license panel; the introduction and project MIT were visible at the top, and scrolling to the bottom showed makelive's author and the final line of its MIT text.

The retained Revive and makelive licenses were compared byte for byte with their pinned upstream versions and match, including Revive's font exception. Documentation separates the project's code from upstream works, Apple platform components, and the AI-assisted icon's provenance. Final package identity is established by the matching release manifest and audit records. Historical release records below do not establish new validation for this build.

---

# 实况工坊 1.11.2（30）

2026-11-05 · 本地交付版本，尚未上传 GitHub

本版纠正 1.11.1 未导入视频时改用整页上下布局的变化，恢复 1.11.0 的左右结构。仅左侧空白视频区域增加导入引导，右侧功能区和原四步使用引导保持原有设计。

## 修正范围

- **左侧导入：** 未导入视频时显示放置框，提供拖入、点击选择和 `⌘O` 入口；不再替换整个主界面。
- **右侧功能保留：** 编辑设置、输出设置、处理按钮与数量角标、已处理入口、添加到照片、隔空投送和导出文件保持原位置；有已有结果时，无需重新导入视频即可从右侧打开列表。
- **恢复原有交互：** 沿用 1.11.0 的批量结果流程、右侧控件和完整四步引导，不采用 1.11.1 的缩减引导逻辑。
- **限定变动：** 与 1.11.0 独立比对，右侧设置、已处理列表、批量模型和引导文件内容一致；应用源代码只在主界面的空态接入、新增导入视图及相应文案处变化。媒体引擎及已有结果存储路径不改。

## 本轮验证

| 范围 | 实际结果 |
| --- | --- |
| 自动测试 | 90 项测试通过，0 失败。 |
| 构建 | 通用测试版与正式构建成功。构建成功不代表另一台 Mac 的运行验收。 |
| 测试版空态 | 现场看到左右完整布局；点击选择文件可以打开面板，取消后回到原空态。 |
| 既有结果 | 右侧「已处理」入口显示并能打开已有 9 项结果。 |
| 使用引导 | 手动打开后看到第 1／4 步；本轮未逐一点击完整四步。 |
| 安装与打包 | 由交付流程核对正式安装应用、版本、安装包及源码包内容和哈希，不以构建或测试版观察代替。 |

本轮未实际重演拖拽、导入后的播放、完整四步引导或新处理输出，也未重新进行照片图库、隔空投送及 iPhone 接收验证。下方版本记录保留为历史证据，不作为 1.11.2 的新验收结果。

## English summary

**LivePhoto Studio 1.11.2 (30)** corrects the full-page stacked empty state introduced in 1.11.1. It restores the 1.11.0 two-column layout and adds the import area only inside the empty left-hand video pane. The right-hand editing/output groups, Process badge, Processed entry, Photos/AirDrop/export actions, batch workflow, and original four-step guide retain their earlier design.

Independent source comparison found the inspector, processed-items view, batch model, and onboarding files identical to 1.11.0. Source changes are limited to the main view's empty-state integration, the new import view, and its strings. Ninety tests passed with zero failures; both the universal test build and production build succeeded. The test build showed the two-column empty state, click-to-open and cancellation, access to nine existing items from the right side, and step 1 of 4 of the manually opened guide. Full drag-and-drop, all guide steps, post-import playback, new processing output, Photos import, AirDrop, and iPhone receipt were not repeated. Installation and package consistency are verified by the delivery workflow.

The app uses system frameworks and does not require FFmpeg, Python, Homebrew, or Xcode to run. Distribution remains ad-hoc signed, without Apple Developer ID signing or notarization. Other Macs may still show macOS source-verification prompts. No GitHub publication has been performed.

---

# 实况工坊 1.11.1（29）

2026-11-05 · 本地交付版本，尚未上传 GitHub

- 未导入视频时显示居中的视频放置框，支持拖入、点击选择和 ⌘O；隐藏尚不可用的编辑设置与处理按钮。
- 已有处理结果时，在放置框下保留「已处理」和批量操作；无需重新导入视频即可查看、添加到照片、隔空投送和导出。
- 导入成功后恢复双栏编辑界面；首次自动引导在导入后出现。手动查看引导时仅聚焦当前可见功能。
- 构建脚本支持 `./build.sh --test "测试用途"`，测试版的中英文显示名称包含测试标记、版本号和用途。
- 本地只保留当前版和上一正式版的安装包，应用程序中保留一个正式应用；打包和测试副本用完清理。

本轮 90 项自动测试通过。独立且明确标注的测试版已验证深色空状态、点击放置框、取消返回、⌘O 选择文件、未导入时打开 9 项处理结果，以及导入 30 秒竖屏视频后恢复双栏、10 秒时间轴和 3 秒选区。未实际重演拖拽高亮、无处理结果状态、浅色/英文空状态、首次自动引导、照片图库或 iPhone 隔空投送。构建和安装包校验由交付流程记录；历史版本的设备测试不作为本版新证据。

**English:** A focused video drop area replaces inactive editor controls before import. Previously processed items remain accessible below it. Click-to-open, cancellation, ⌘O, collection access, and the transition to the editor were checked in a labeled test build; 90 tests passed. Test builds include a version and purpose in their display names. Distribution remains ad-hoc signed and not notarized.

---

# 实况工坊 1.11.0（28）

2026-11-05 · 本地交付版本，尚未上传 GitHub

本版整理右侧功能分组，并统一处理结果的命名。沿用已经调整好的裁切、水印、时间轴和批量流程；媒体处理引擎与已有文件的存储路径不变。

## 界面与文案

- **编辑设置：** 裁切、旋转、水印和静音归入同一组，保留原有控件与交互。
- **输出设置：** 实况／GIF、原画质／自定义及尺寸、帧率参数归入另一组。两组使用独立浅底区域、统一留白和更明显的标题。
- **操作层级：** 「处理」继续作为主要按钮，数量角标与批量入口保留；添加到照片、隔空投送、导出文件集中在下方。
- **统一命名：** 原「成品」入口改为「已处理」，原「成品设置」改为「存储与清理」，说明文字统一称「处理结果」；同步更新英文与首次使用引导。
- **保留既有结果：** 本轮不迁移或更名 `LivePhotoStudio/Finished`，不改变自动清理默认关闭的规则。

## 本轮验证

以下记录本轮已经观察或核验的结果。安装包、已安装应用与公开源码的一致性由打包流程校验。下方 1.10.0 的测试和设备接收记录属于历史版本，不能作为本版已经完成验证的证明。

| 范围 | 当前状态 |
| --- | --- |
| 自动测试与通用构建 | 本轮 90 项测试通过，0 失败；arm64／x86_64 通用构建与系统依赖审计通过。 |
| 安装版界面 | 最终安装版的浅色英文界面已用 4K 横向素材现场确认，灰色窗口底与两张白色卡片区分清楚，控件完整显示；返回深色中文主界面后，卡片、3 秒选区和按钮顺序均完整。 |
| 时间轴 | 已观察 30 秒竖屏视频默认展示 10 秒范围，并保留 3 秒选区。 |
| 裁切与水印 | 已检查裁切比例菜单及 720 × 720 的「完成裁切」状态；自由水印位置参数和重新编码提醒保留。 |
| 处理与持久化 | 点击「处理」后数量角标从 8 增至 9，重启后 9 项处理结果仍在；「已处理」新名称已确认。 |
| 实况预览 | 本轮新生成的裁切＋水印实况已在系统实况视图中加载并启动播放；未将此观察视为完整播放回归。 |
| 窗口布局 | 已观察约 996 × 751 和 1184 × 1011 的常用窗口，以及放大／恢复；工具未成功调整到精确 900 × 640，因此最小窗口验证未完成。 |
| UI 批量文件导出 | 在安装版点击导出 9 项，生成 17 个平铺文件（8 JPG、8 MOV、1 GIF），没有子目录；文件 SHA-256 集合与处理库对应媒体一致，9 项处理结果仍保留。 |
| 系统服务 | 本轮未重新测试添加到照片、隔空投送接收或 iPhone LIVE 播放。 |
| 关于与设置 | 正式安装版关于面板已确认 1.11.0（28）、latter404、MIT 及引用标注；「存储与清理」的三个自动删除开关均关闭，默认路径未变，语言和外观已恢复跟随系统。 |
| 正式产物 | 安装包、已安装应用、公开源码和许可随打包流程进行内容及哈希校验。 |

## English summary

**LivePhoto Studio 1.11.0 (28)** groups the right-side controls into **Editing** and **Output**, strengthens section headings, and retains the existing crop, watermark, timeline, and batch workflows. **Process** remains the primary action. The collection is now called **Processed**, and its storage preferences are named **Storage & Cleanup**. Existing files remain at the same location; cleanup remains off by default.

So far, 90 tests have passed with zero failures, the arm64/x86_64 universal build has succeeded, and the system-dependency audit has passed. The installed build has been inspected in Chinese, English, and dark appearance. A 30-second portrait source showed the default ten-second timeline and three-second selection. Crop controls, the 720 × 720 crop-completion state, free watermark positioning parameters, and the re-encoding notice were retained. Processing increased the count from eight to nine, with all nine items still present after relaunch.

Window layouts at approximately 996 × 751 and 1184 × 1011, plus enlarge/restore, have been inspected. The tool did not reach the exact 900 × 640 minimum, so that check remains incomplete. The final installed build's English light appearance was checked with a landscape 4K source: the two white groups are distinct from the gray window background, and all controls are visible. Exporting nine selected items through the UI produced 17 flat files (eight JPG, eight MOV, and one GIF), with no subfolders. Their SHA-256 collection matched the corresponding stored media, and all nine processed items remained available.

The newly created cropped and watermarked Live Photo loaded in the system Live Photo view and playback was started; this observation is not a full playback regression check. The installed About panel was verified to show 1.11.0 (28), latter404, MIT, and upstream attribution. The **Processed** name and all nine items were confirmed. All three automatic-deletion settings are off, the default storage path is unchanged, and language and appearance were restored to follow the system. The final Chinese dark-appearance screen was also observed with its grouped cards, three-second selection, and action order intact.

Photos import, AirDrop receipt, and iPhone LIVE playback have not been repeated this cycle. The packaging workflow checks bundle contents, installed-build identity, public source, and license files. The 1.10.0 records below are historical evidence. Distribution remains ad-hoc signed, without Apple Developer ID signing or notarization; no GitHub publication has been performed.

---

# 实况工坊 1.10.0（27）

2026-11-05 · 本地交付版本，尚未上传 GitHub

本版加入成品累积与批量操作。选好片段后先点「处理」，再从数量角标打开成品列表；添加到照片、隔空投送和导出文件统一作用于已选成品。

## 新增与改进

- **连续制作：** 同一视频可以制作多个片段，也可以更换视频继续累积。每项成品保留独立的画面、封面和处理结果，后续编辑不会改变它。
- **成品列表：** 支持预览、多选、批量操作和移除；退出应用后仍然保留。
- **批量导出：** 实况导出为配对的 JPG＋MOV，GIF 导出为 GIF 文件；平铺到所选目录，不创建每张独立文件夹，不覆盖同名文件。导出位置不能位于成品库内部。
- **成品设置：** 可分别设置添加到照片、隔空投送、导出后是否清理，默认全部关闭。清理将应用内成品移到系统废纸篓，不删除原视频、图库项目或导出副本。
- **保存位置：** 可迁移成品库，核对新位置副本后再切换；旧位置副本可从废纸篓恢复。
- **首次引导：** 四步高亮说明导入、处理、选择成品及统一操作，可跳过或重新查看。

## 隔空投送的完成与清理

本轮在 macOS 27.2 实测发现：即使取消隔空投送，系统也可能调用 `didShareItems`。因此，应用不会把窗口关闭或该回调当作接收端已经收到并识别实况的证明。

开启「隔空投送后清理」时，系统窗口结束后仍需确认接收成功，才会将所选成品移到废纸篓。选择「保留」不会删除成品。未开启此设置时，成品继续保留，方便重新发送。

## 本轮验证

以下是当前版本实际观察或核验的结果，不代表全部设备均已通过：

| 范围 | 结果 |
| --- | --- |
| 自动测试 | 90 项测试全部通过，0 失败，包含新增 GIF 解码回归。 |
| GIF 成品预览 | 最终安装版已观察到连续帧变化，播放与停止正常；预览尺寸受限，未撑大窗口。 |
| Finder 入口 | 一级右键菜单「转为实况照片」可直接将测试视频导入已安装版本。 |
| 界面与关于信息 | 英文主界面、关于窗口中的 1.10.0（27）、作者署名及 MIT／第三方许可已现场核对。 |
| 成品持久化 | 累积 10 项成品，重新打开应用后仍保留。 |
| 添加到照片 | 3 项批量添加到本机照片图库，实况标识可见。 |
| iPhone 接收 | 用户明确确认本轮发送的 3 项在 iPhone 上接收正常，实况可播放。 |
| 批量文件导出 | 3 项实况生成 6 个平铺文件；导出副本与对应成品原件的文件哈希一致。 |
| GIF 与混合导出 | 720 × 1280、30 fps、3 秒 GIF 按原尺寸生成成功；与一张实况混合批量导出，得到 3 个平铺 GIF／JPG／MOV 文件，哈希均与对应成品一致。 |
| 导出后清理 | 开启清理后，仅将所选 3 项成品移到废纸篓；其余 7 项成品和目标目录中的 12 个导出文件均保留。 |
| 成品库迁移 | 7 项成品迁到新位置，再迁回默认位置，文件哈希核对一致。 |
| 取消隔空投送 | 最终版本取消后操作按钮恢复；开启清理时选择「保留」，成品没有被误删。 |

## 当前限制

- 应用及 Finder 扩展包含 Apple 芯片与 Intel 架构，最低系统要求为 macOS 14；本轮界面与系统服务实测环境为 macOS 27.2。
- 当前仍为 ad-hoc 签名，尚未完成 Apple Developer ID 签名与公证。其他电脑的安装行为受 macOS 来源验证和设备策略影响。
- 本轮没有完成 Intel、旧版 macOS 或其他人的 M2 Max 设备实机验证。一次 iPhone 成功接收也不代表所有系统版本、接收设备和第三方应用均兼容。
- 4K、8K 在本轮覆盖的是尺寸、方向、水印等几何回归，不是全部编码、帧率、HDR、GIF 组合的完整导出矩阵。
- 原画质视频复制仅适用于源编码支持直接封装，且未添加水印、未实际裁切、未启用自定义参数的场景。旋转本身修改方向信息。水印、裁切或自定义输出需要重新编码，当前处理链输出 SDR。
- 原尺寸高分辨率 GIF 仍可能消耗明显时间、内存和磁盘空间；GIF 最多 256 色、无声音，帧率上限 50 fps。

## English summary

**LivePhoto Studio 1.10.0 (27)** adds a persistent finished-item collection. Process clips first, then preview and select items for batch Photos import, AirDrop, or flat file export. Cleanup is optional for each action and off by default; it moves finished items to Trash. Storage migration and a four-step first-use guide are included.

**AirDrop cleanup requires receipt confirmation.** On macOS 27.2, cancellation was observed to trigger `didShareItems` in some cases. Closing the system window is not proof of delivery. With cleanup enabled, the user must confirm successful receipt before items are removed; choosing **Keep** preserves them.

Validation for this build includes 90 passing tests, including GIF decoder regression tests, persistence of 10 finished items, three items added to Photos with LIVE indicators, and explicit user confirmation that three items were received and played as Live Photos on an iPhone. Batch-export hashes matched the source finished items. An original-size 720 × 1280, 30 fps, three-second GIF was generated and exported together with one Live Photo; all three flat GIF/JPG/MOV files matched their corresponding finished-item hashes. Selected-only cleanup and a seven-item storage migration round trip were also checked. Cancelling AirDrop restored the controls without deleting items when **Keep** was selected.

This is an ad-hoc-signed local build and has not been uploaded to GitHub or notarized with Apple. Intel, older macOS releases, and another user's M2 Max have not been verified on actual hardware in this cycle. The 4K/8K coverage here is geometry regression, not a complete encoding and device compatibility matrix.
