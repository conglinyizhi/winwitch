# 字母切窗 (Letter Switch)

KDE Plasma 6 / Wayland 下的窗口切换器。按 `Meta+F` 进入选择模式，任务栏图标右上角显示
字母标签，按字母切到对应窗口，`Esc` 立即退出且不切换任何窗口。

```
Meta+F              进入选择模式，显示标签
Meta+F, <字母>       切到该字母对应的窗口
Meta+F, Escape      取消，不切换窗口
```

## 为什么是这三个部分

Plasma 6 Wayland 下，「进入模式后吃掉下一个任意按键」不能只靠 QML 小部件完成，
也不能让普通进程随便读键盘设备。所以职责拆成三层：

| 部分 | 位置 | 职责 |
| --- | --- | --- |
| 状态机与协议 | `core/`（MoonBit） | 字母分配、`Esc` 优先级、会话 token、超时 |
| 会话服务 | `cmd/main/`（MoonBit + moondbus） | 把状态机以 D-Bus 服务暴露给 KWin 和 Plasma |
| 窗口与显示 | `kwin/`、`package/` | KWin 枚举/激活窗口；QML 画标签 |

MoonBit 侧不接触键盘设备、不写文件；KWin 侧不保存状态。两侧通过 D-Bus 交换字符串，
不比较窗口 ID 的跨进程一致性：任务栏按自己的顺序算标签，KWin 按同一顺序激活。

## 安装

```bash
scripts/install.sh
```

脚本会：编译 helper 到 `~/.local/bin/letterswitch`，安装 KWin 脚本与任务栏组件，
写自启动项。之后还需手动完成：

1. 手动跑一次 helper：

   ```bash
   nohup stdbuf -oL letterswitch >/tmp/letterswitch.log 2>&1 &
   ```

   `stdbuf -oL` 不能省：MoonBit 的 stdout 在重定向到文件时是全缓冲，不加就看不到任何日志。

2. 系统设置 → 窗口管理 → KWin 脚本，确认「字母切窗」已勾选。
3. 面板添加「字母切窗标签」组件。

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

### 仍未验证

1. **按实际的 `Meta+F, <字母>` 键序列能否触发**。快捷键已注册成功，但键序列是否被 KDE 真正派发，需你亲手按一下。
   若无效，把 `kwin/contents/code/main.js` 里的 `useSequences` 默认值改 `false`，退到 `Meta+Alt+<字母>`。
2. **按字母后的窗口激活那一段**。不偷你桌面焦点，所以没测；你按一次就知道。
3. **任务栏组件在面板上的实际渲染**。包已正确安装，但尚未添加到面板。

## 排查笔记

两个坑，都已在代码里处理：

- **Qt 客户端会先发 Introspect**。qdbus6 这类 Qt 客户端在调用方法前会请求
  `org.freedesktop.DBus.Introspectable.Introspect` 解析签名。服务端若不回包，客户端会一直等，
  表现为「调用挂死」而不是报错。helper 现在实现了自省回复与 `Peer.Ping`。
- **KWin 脚本的 metadata 必须有 `KPackageStructure`**。只写已弃用的 `ServiceTypes` 时，
  KWin 会拒收并报 `does not match requested format "KWin/Script"`，而且坏 metadata 装上后
  `kpackagetool6 --upgrade` 也认不出这个包，安装脚本因此改成先移除再安装。

helper 的逐调用日志默认关闭（任务栏会持续轮询，打开会刷满日志）：
排障时用 `LETTERSWITCH_DEBUG=1 letterswitch` 启动。

## 已知限制

- 字母上限 26 个窗口，超出的窗口不显示标签。
- 任务栏组件是独立实现，不是系统任务栏的补丁；它不会修改 `/usr/share` 下的任何文件，
  但也不会把标签叠加到系统任务栏上，需要用它替代原任务栏。
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
core/           纯逻辑：标签分配 + 会话状态机（无外部依赖，任何后端可测）
cmd/main/       D-Bus 会话服务
kwin/           KWin 脚本包
package/        Plasma 任务栏组件包
data/           自启动项
scripts/        安装与卸载
```

`moondbus` 目前只解出字符串与 u32，所以整套 IPC 刻意只用字符串，两端都不解析整数。
