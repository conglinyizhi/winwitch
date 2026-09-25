# 字母切窗 (Letter Switch)

KDE Plasma 6 / Wayland 下的窗口切换器。按 `Meta+F` 进入选择模式，屏幕底部浮出一排字母，
按字母切到对应窗口，`Esc` 立即退出且不切换任何窗口。

```
Meta+F              进入选择模式，浮出可用字母
Meta+F, <字母>       切到该字母对应的窗口
Meta+F, Escape      取消，不切换窗口
```

## 标签显示形态

三种形态，当前部署的是第三种：

- **替代任务栏**：字母直接画在任务栏图标右上角，所见即所得。代价是用一个精简版任务栏
  换掉系统任务栏，会丢掉分组、悬停预览等行为。
- **面板字母条**（`package/`，保留但默认不安装）：面板上一个窄组件，占一格面板位置。
- **浮层（当前）**：独立进程，选择模式期间在屏幕底部浮出一排卡片
  （字母 + 应用图标 + 应用名 + 窗口标题），结束后消失。可见内容不占面板。

浮层**没有自动超时**：退出只靠 `Esc` 或选中某个字母。曾经加过 8 秒兜底被否掉了。

### 设置页

面板上的「字母切窗 顺序源」有一个小而淡的窗口图标，**点它就弹出设置**。目前三项：

| 选项 | 说明 |
| --- | --- |
| 浮层位置 | 屏幕底部居中 / 屏幕中央 / 屏幕顶部居中 |
| 最多几列 | 卡片每行最多排几张 |
| 显示窗口标题 | 应用名下面那行小标题是否显示 |

配置怎么走到浮层的：浮层是独立进程，读不到面板组件的配置，所以借 helper 中转——

```
设置页 → 顺序源每秒推送 → helper 的 Config → 快照里的 @config 行 → 浮层解析生效
```

### 字母顺序怎么对齐任务栏

这里有个必须知道的坑：**KWin 枚举窗口的顺序与任务栏图标顺序不一致**。
实测同一时刻，任务栏第 0 位是飞书，而 KWin 第 0 位是 Kate。只靠 KWin 无法让
「A = 任务栏第一个图标」成立。

解决办法是面板上一个**零宽度**的「顺序源」组件（`panel/`）：

- 它读 Plasma 的任务模型，按任务栏顺序取出 `WinIdList`；
- 实测这个值就是 KWin 的 `internalId`（UUID），能直接对齐；
- 它把顺序推给 helper（D-Bus 的 `Order`），helper 据此重排字母；
- 同时带出应用名、图标名与窗口标题，浮层就用这些画卡片。

两个细节，都是踩出来的：

- **固定应用（常驻图标）必须占一个字母位，而且得自己拼进顺序里**。
  任务栏把它们放在最前面，但公开的任务模型**没有 `launchers` 属性**
  （实测 `tasks.launchers === undefined`，和 `filterByCurrentDesktop` 一样被裁掉了），
  所以顺序源改为读任务栏配置的 `launchers=`，逐项占位并对上在跑的窗口；
  `preferred://filemanager` 这类符号名用 `xdg-mime query default inode/directory` 解析。
- **启动器图标（常驻应用）必须占一个字母位**。它们没有窗口，若直接跳过，
  后面所有字母都会相对图标前移一位——用户看到的就是「顺序不完全一致」。
  现在会为它们空掉一个字母。
- **顺序源每次都要推，不能做「内容没变就跳过」的去重**。helper 重启后之前推过的顺序
  就丢了，而面板以为自己推过了，于是永远不再推——字母静默退回 KWin 顺序，
  表现就是「有些能对上、有些对不上」。这个坑很难从现象看出来。
- **图标名要从 desktop 文件的 `Icon=` 取**，不能按应用标识猜：
  `org.kde.kate` 的图标其实叫 `kate`。而任务模型的 `AppIconName` 角色实测返回的是展示文本。
  面板组件按应用标识查一次 desktop 文件并缓存（命令走 shell，可以直接读）。

为什么必须是面板组件：独立进程读不了任务模型——一实例化 `TaskManager.TasksModel`
整个 QML 就加载失败（实测：`Did not load any objects, exiting.`）。

因此「面板上完全不出现任何东西」是做不到的：顺序源会在面板配置里占一项，
但它不绘制任何内容（零尺寸）。

## 为什么是这几个部分

Plasma 6 Wayland 下，「进入模式后吃掉下一个任意按键」不能只靠 QML 小部件完成，
也不能让普通进程随便读键盘设备。所以职责拆开：

| 部分 | 位置 | 职责 |
| --- | --- | --- |
| 状态机与协议 | `core/`（MoonBit） | 字母分配、`Esc` 优先级、会话 token |
| 会话服务 | `cmd/main/`（MoonBit + moondbus） | 把状态机以 D-Bus 服务暴露给 KWin 和浮层 |
| 键盘与窗口 | `kwin/` | 注册快捷键、枚举/激活窗口 |
| 显示 | `overlay/` | 独立进程，浮出字母并做超时兜底 |

MoonBit 侧不接触键盘设备、不写文件；KWin 侧不保存状态；超时由浮层负责。
三方通过 D—Bus 交换字符串。

## 安装

```bash
scripts/install.sh
```

改完代码之后重新装载用：

```bash
scripts/reload.sh     # 重装 + 重启 helper/浮层 + 冒烟测试
```

这个脚本不是图省事：里面几个顺序（开关插件重载 KWin 脚本、按 QML 路径杀浮层实例）
都是踩出来的，手敲很容易漏。详见下面的排查笔记。

安装脚本会：编译 helper 到 `~/.local/bin/letterswitch`，安装 KWin 脚本、
浮层（`~/.local/share/letterswitch/overlay/`）、两个自启动项，并清掉旧的面板组件。
之后只需确认：系统设置 → 窗口管理 → KWin 脚本，看「字母切窗」是否已勾选。

helper 的启动需要 `stdbuf -oL`（自启动项里已经写好了）：
MoonBit 的 stdout 重定向到文件时是全缓冲，不加就看不到任何日志。

自检：

```bash
qdbus6 org.clyzhi.LetterSwitch /LetterSwitch org.clyzhi.LetterSwitch.Status
# 空闲时应输出：idle:t0
```

卸载：

```bash
scripts/uninstall.sh
```

## D-Bus 接口

服务名 `org.clyzhi.LetterSwitch`，对象路径 `/LetterSwitch`，接口同名。

| 方法 | 参数 | 返回 |
| --- | --- | --- |
| `Begin` | 窗口 ID，制表符分隔 | `<token>\t<字母=窗口>\t…` |
| `Key` | `<token>:<按键>` | `activate:<窗口>` / `cancel` / `ignore` |
| `Cancel` | `<token>` | `cancel` / `ignore` |
| `Status` | 无 | 快照：首行 `idle:<token>` 或 `selecting:<token>:<字母=窗口>…`，其后每行 `字母\ttitle\tapp_id` |
| `Note` | 文本 | `ok`（界面把自身状态回抛给 helper，便于一处排查） |
| `Order` | 窗口 ID，逗号分隔 | `ok`（面板顺序源推送的任务栏顺序，用于重排字母） |

约定：

- 字母表顺序为 `ASDFGHJKLQWERTYUIOPZXCVBNM`（主行 → 上排 → 下排），`core` 与 QML 各有一份，改动需同时改。
- `Escape` 的优先级高于任何字母匹配：即使映射为空或窗口列表已失效，也只取消，不激活。
- 每次进入或退出选择模式都会更换 token，陈旧事件一律 `ignore`。

## 已验证 / 未验证

### 已在你本机实测通过
- `core` 单元测试 37 项全绿。
- **KWin 接受并加载了脚本**：`isScriptLoaded letterswitch` → `true`，journal 有「已注册，入口 Meta+F（组合序列）」。
- **28 条快捷键真实注册**：`kglobalaccel` 的 kwin 组件里数得到 26 个字母 + 进入选择模式 + 取消。
- **Meta+F 处理器全链路跑通**：主动触发「字母切窗 进入选择模式」后，KWin 枚举出真实会话的 12 个窗口，
  helper 按顺序分配 `A S D F G H J K L Q W E R`，`Status` 返回 `selecting:t7:...`；再触发取消回到 `idle:t8`。
- **三种 D-Bus 客户端都能稳定调用**：gdbus、busctl、qdbus6 各三轮均返回；连轮询 30 次无超时、无残留进程。
- **按 `Meta+F` 确实会触发**。journal 里能数到多次「选择模式开始 token=t…」与随之的「已取消」，
  对应实际按键；测试时也曾误判为「没反应」，实际是当时没有任何可见反馈。
- **4 秒超时生效**：触发后不操作，状态会自动回到 `idle`。
- **字母条已在面板上运行**：开调试日志后测到每 3 秒 12 次 `Status`，正好对应 250ms 轮询周期。

### 仍未验证

1. **按字母后的窗口激活那一段**。不偷你桌面焦点，所以没测；按一次就知道。
2. **字母条的实际视觉效果**。终端里无法确认渲染，见下。

## 本机部署状态

- 仓库：`~/disk/ai_workspace/kde-winwitch`
- helper：`~/.local/bin/letterswitch`，由 `~/.config/autostart/letterswitch-helper.desktop` 自启
- KWin 脚本：已启用（`kwinrc` 的 `letterswitchEnabled=true`）
- 浮层：`~/.local/share/letterswitch/overlay/main.qml`，由 `letterswitch-overlay.desktop` 自启
- 面板：已清空，不留任何本项目的组件

## 排查笔记

两个坑，都已在代码里处理：
- **Qt 客户端会先发 Introspect**。qdbus6 这类 Qt 客户端在调用方法前会请求
  `org.freedesktop.DBus.Introspectable.Introspect` 解析签名。服务端若不回包，客户端会一直等，
  表现为「调用挂死」而不是报错。helper 现在实现了自省回复与 `Peer.Ping`。
- **KWin 脚本的 metadata 必须有 `KPackageStructure`**。只写已弃用的 `ServiceTypes` 时，
  KWin 会拒收并报 `does not match requested format "KWin/Script"`，而且坏 metadata 装上后
  `kpackagetool6 --upgrade` 也认不出这个包，安装脚本因此改成先移除再安装。

helper 的逐调用日志默认关闭（面板组件会持续轮询，打开会刷满日志）：
排障时用 `LETTERSWITCH_DEBUG=1 letterswitch` 启动。

另外两个耗了不少时间的坑：

- **改完组件 QML 必须重启 plasmashell**。重装包、删 QML 缓存、甚至删掉面板上的组件再重新添加，
  都不足以让 plasmashell 用上新文件；它会继续跑内存里的旧代码。
  改完记得 `systemctl --user restart plasma-plasmashell.service`。
- **不要指望 KWin 脚本里的 `callLater` 做超时**。实测它有时不触发，选择模式会永久停在选中状态。
  现在由面板组件的 Timer 做看门狗（8 秒），只要组件在跑就能收手。
- **改 KWin 脚本要开关一次插件才算重载**。`qdbus6 org.kde.KWin /KWin reconfigure` 不会重载已重装过的脚本；
  也不能用 `Scripting.unloadScript` + `loadScript`，那样会留下僵尸动作——旧动作还在 kglobalaccel，
  新实例用同名注册被拒，结果动作指向已死的实例，表现就是「按了没反应，日志也没记录」。
- **杀浮层要按 QML 路径匹配**。实际进程是 `/usr/bin/qml .../letterswitch/overlay/main.qml`，
  按包装脚本名 pkill 匹配不到，每次重载会多留一个实例，多个浮层叠在一起。
- **命令是交给 shell 解释的，载荷里的 shell 元字符必须先处理**。引擎用的是
  `KProcess::setShellCommand`，所以：
  - `|` 会被当成管道（`Note p|boot` 只传过去一个 `p`）；
  - `;` 会被当成命令分隔符（`Config position=bottom;columns=6` 只传过去第一段）。
  带特殊字符的载荷统一用顺序源里的 `shellQuote()` 整体加引号；纯状态上报才用字符白名单。
- **不要用 `console.*` 传诊断信息**。`console.info` 走 qDebug，默认不进 journal；
  面板报错行号在多处补丁后会指向无关行，徒劳增加排查成本。
  组件的上报统一走 helper 的 `Note` 方法，日志落在同一个地方。

## 已知限制

- 字母上限 26 个窗口，多余的窗口没有字母。
- 字母映射基于「任务栏顺序」：顺序源推的顺序每秒刷新一次，若你在选择模式中拖动任务栏图标，
  字母会跟着变。
- 面板配置里会有一项「字母切窗 顺序源」；它不显示内容，但确实占一项。
  不需要时右键移除即可（移除后字母会退回到 KWin 顺序）。
- helper 必须常驻；未运行时浮层不显示（隐藏是安全的默认值），`Meta+F` 不会生效。
- 未实现：多屏分组、按应用分组、虚拟桌面跨屏切换、标签颜色配置。

## 开发

```bash
moon test                        # core 单元测试
moon build cmd/main --target native
moon fmt
moon info
```

目录：

```
core/           纯逻辑：字母分配 + 会话状态机（无外部依赖，任何后端可测）
cmd/main/       D-Bus 会话服务
kwin/           KWin 脚本包
overlay/        浮层（独立进程，qml6 运行）
panel/          面板顺序源（零尺寸，把任务栏顺序推给 helper）
package/        面板字母条组件（保留，默认不安装）
data/           自启动项
scripts/        安装、重载、卸载
```

`moondbus` 目前只解出字符串与 u32，所以整套 IPC 刻意只用字符串，两端都不解析整数。
