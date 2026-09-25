# 字母切窗 (Letter Switch)

KDE Plasma 6 / Wayland 下的窗口切换器。按 `Meta+F` 进入选择模式，屏幕底部浮出一排字母，
按字母切到对应窗口，`Esc` 立即退出且不切换任何窗口。

```
Meta+F              进入选择模式，浮出可用字母
Meta+F, <字母>       切到该字母对应的窗口
Meta+F, Escape      取消，不切换窗口
```

## 标签显示形态

三个形态，当前部署的是第三个：

- **替代任务栏**：字母直接画在任务栏图标右上角，所见即所得。代价是用一个精简版任务栏
  换掉系统任务栏，会丢掉分组、悬停预览等行为。
- **面板字母条**（`package/`，保留但默认不安装）：面板上一个窄组件，占一格面板位置。
- **浮层（当前）**：独立进程，选择模式期间在屏幕底部浮出一排字母，结束后消失。
  面板上不留任何东西。

浮层**无法与任务栏图标逐个对齐**：那需要自己接管任务栏渲染。
浮层能做到的是「选择模式时浮出一排可用字母」。

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
| `Status` | 无 | `idle:<token>` / `selecting:<token>:<字母=窗口>…` |
| `Note` | 文本 | `ok`（浮层把自身状态回抛给 helper，便于一处排查） |

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
- **不要用 `console.*` 传诊断信息**。`console.info` 走 qDebug，默认不进 journal；
  面板报错行号在多处补丁后会指向无关行，徒劳增加排查成本。
  组件的上报统一走 helper 的 `Note` 方法，日志落在同一个地方。

## 已知限制

- 字母上限 26 个窗口，多余的窗口没有字母。
- 字母条只显示字母，不显示字母对应哪个窗口：KWin 枚举窗口的顺序与任务栏模型的手工排序
  未必一致，硬对应会显示错误映射。要所见即所得，需要用「替代任务栏」那个形态。
- 字母条会在面板上占一小格位置；不需要时右键移除。
- helper 必须常驻；未运行时标签不显示（隐藏是安全的默认值），`Meta+F` 不会生效。
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
package/        面板字母条组件（保留，默认不安装）
data/           自启动项
scripts/        安装、重载、卸载
```

`moondbus` 目前只解出字符串与 u32，所以整套 IPC 刻意只用字符串，两端都不解析整数。
