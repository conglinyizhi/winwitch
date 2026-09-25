// 会话总线服务：字母选择会话的唯一权威。
//
// KWin 通过 D-Bus 驱动它，Plasma 任务栏组件通过 D-Bus 查询标签。
// 本进程不接触键盘设备，也不写任何文件。

///|
let service_name : String = "io.github.conglinyizhi.WindowNavigator"

///|
let object_path : String = "/WindowNavigator"

///|
let interface_name : String = "io.github.conglinyizhi.WindowNavigator"

///|
/// 把纯文本包成一个 `s` 类型的回复。
fn string_reply(text : String) -> @dbus.Reply {
  let encoder = @dbus.Encoder::new()
  encoder.string(text)
  @dbus.Reply::make(encoder.finish(), "s")
}

///|
/// 无正文、无签名的回复（用于 `org.freedesktop.DBus.Peer.Ping`）。
fn empty_reply() -> @dbus.Reply {
  @dbus.Reply::make(b"", "")
}

///|
/// 逐调用日志默认关闭。任务栏组件会持续轮询，默认打开会把日志刷满；
/// 排障时用 `LETTERSWITCH_DEBUG=1` 启动 helper 即可打开。
fn debug_enabled() -> Bool {
  match @env.get_env_var("LETTERSWITCH_DEBUG") {
    Some(v) => v != "" && v != "0"
    None => false
  }
}

///|
/// 读取方法调用的第一个字符串参数。
///
/// moondbus 的 `read_dbus_string(body, 0)` 对单参数调用成立；带额外 header 字段的
/// 调用正文可能从 8 字节边界开始，所以这里额外试一次偏移 8。偏移不匹配时返回空串，
/// 由上层按「空参数」处理，不会读到越界内容。
fn first_arg(body : Bytes) -> String {
  match @dbus.read_dbus_string(body, 0) {
    Some(text) => if text != "" { return text }
    None => ()
  }
  match @dbus.read_dbus_string(body, 8) {
    Some(text) => text
    None => ""
  }
}

///|
/// 把处理结果编码成一行，供 KWin 解析。
fn describe(action : @core.Action) -> String {
  match action {
    Activate(window_id) => "activate:" + window_id
    Cancel => "cancel"
    Timeout => "timeout"
    Ignore => "ignore"
  }
}

///|
fn dispatch(session : @core.Session, ctx : @dbus.DispatchCtx) -> @dbus.Reply {
  if debug_enabled() {
    println(
      "windownavigator: 收到调用 iface=\"\{ctx.iface}\" member=\"\{ctx.member}\" body_len=\{ctx.body.length()}",
    )
  }
  // 自省与 Peer 属于 D-Bus 约定的公共接口，不在我们的接口名下。
  // 特别是 Introspect：Qt 系客户端靠它解析签名，不回包会直接挂死调用。
  if ctx.iface == "org.freedesktop.DBus.Introspectable" &&
    ctx.member == "Introspect" {
    return string_reply(@core.introspection_xml())
  }
  if ctx.iface == "org.freedesktop.DBus.Peer" && ctx.member == "Ping" {
    return empty_reply()
  }
  if ctx.iface != interface_name {
    return string_reply("error:unknown-interface")
  }
  match ctx.member {
    // 参数：窗口列表，每行 `id\t标题\t应用标识`，顺序即字母顺序。
    // 返回：`<token>\t<字母=窗口>\t...`
    "Begin" => {
      let tasks = @core.parse_tasks(first_arg(ctx.body))
      let labels = session.begin_tasks(tasks)
      string_reply(session.token() + "\t" + @core.encode_labels(labels))
    }
    // 参数：`<token>:<按键>`。返回 `activate:<窗口>` / `cancel` / `ignore`。
    "Key" => {
      let (token, key) = match @core.split_once(first_arg(ctx.body), ':') {
        Some(pair) => pair
        None => ("", "")
      }
      string_reply(describe(session.handle_key(token, key)))
    }
    // 参数：`<token>`。返回 `cancel` / `ignore`。
    "Cancel" =>
      string_reply(describe(session.handle_cancel(first_arg(ctx.body))))
    // 返回快照：第一行 `idle:<token>` 或 `selecting:<token>:<字母=窗口>...`，
    // 其余每行 `字母\ttitle\tapp_id`，界面一次查询就能把字母与窗口对应起来。
    "Status" => string_reply(session.snapshot())
    // 界面层把自己的状态回抛给 helper，日志就能落在一个地方。
    // 依赖：面板里的 console 既不保证输出，也不保证不会抛错。
    "Note" => {
      println("windownavigator[界面] \{first_arg(ctx.body)}")
      string_reply("ok")
    }
    // 界面推来的外观配置（`键=值;键=值`）。浮层读不到面板组件的配置，
    // 所以经这里中转，随快照的 `@config=` 行发出去。
    "Config" => {
      session.set_config(first_arg(ctx.body))
      string_reply("ok")
    }
    // 取走待激活的窗口。界面选完之后触发 KWin 的「提交」动作，KWin 再来调这个。
    "TakePending" =>
      match session.take_pending() {
        Some(id) => string_reply("activate:" + id)
        None => string_reply("none")
      }
    // 面板组件报来的任务栏槽位（每行 `<窗口 ID 逗号分隔>\t应用名\t图标名\t标题`）。
    // KWin 的枚举顺序与任务栏不一致，靠这个把字母对齐到图标位置；
    // 启动器行没有窗口但占一个字母位，否则后面的字母会与图标错开。
    "Order" => {
      let body = first_arg(ctx.body)
      if debug_enabled() {
        println("windownavigator: 收到顺序槽位（每行：ids	应用名	图标名	标题）")
        for line in @core.split_char(body, '\n') {
          if line != "" {
            println("  " + line)
          }
        }
      }
      let slots = @core.parse_slots(body)
      session.set_slots(slots) |> ignore
      string_reply("ok")
    }
    _ => string_reply("error:unknown-method")
  }
}

///|
fn main {
  match @dbus.Server::connect() {
    Err(code) =>
      println("windownavigator: 无法连接会话总线，错误码 \{code}")
    Ok(server) => {
      match server.hello() {
        Ok(unique) =>
          println("windownavigator: 已连接会话总线，唯一名 \{unique}")
        Err(code) =>
          println("windownavigator: Hello 握手失败，错误码 \{code}")
      }
      match server.request_name(service_name, 0) {
        Ok(_) => println("windownavigator: 已申请名称 \{service_name}")
        Err(code) =>
          println(
            "windownavigator: 申请名称 \{service_name} 失败，错误码 \{code}；KWin 将无法调用本服务",
          )
      }
      let session = @core.Session::new()
      println("windownavigator: 就绪，对象路径 \{object_path}")
      server.serve(fn(
        _server : @dbus.Server,
        ctx : @dbus.DispatchCtx,
      ) -> @dbus.Reply? {
        Some(dispatch(session, ctx))
      })
    }
  }
}
