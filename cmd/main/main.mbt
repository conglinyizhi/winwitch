// 会话总线服务：字母选择会话的唯一权威。
//
// KWin 通过 D-Bus 驱动它，Plasma 任务栏组件通过 D-Bus 查询标签。
// 本进程不接触键盘设备，也不写任何文件。

///|
let service_name : String = "org.clyzhi.LetterSwitch"

///|
let object_path : String = "/LetterSwitch"

///|
let interface_name : String = "org.clyzhi.LetterSwitch"

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
      "letterswitch: 收到调用 iface=\"\{ctx.iface}\" member=\"\{ctx.member}\" body_len=\{ctx.body.length()}",
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
    // 参数：窗口 ID 列表，制表符分隔，顺序即任务栏顺序。
    // 返回：`<token>\t<字母=窗口>\t...`
    "Begin" => {
      let windows = @core.split_char(first_arg(ctx.body), '\t')
      let labels = session.begin(windows)
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
    // 返回 `idle:<token>` 或 `selecting:<token>:<字母=窗口>...`。
    "Status" => string_reply(session.encode())
    _ => string_reply("error:unknown-method")
  }
}

///|
fn main {
  match @dbus.Server::connect() {
    Err(code) =>
      println("letterswitch: 无法连接会话总线，错误码 \{code}")
    Ok(server) => {
      match server.hello() {
        Ok(unique) =>
          println("letterswitch: 已连接会话总线，唯一名 \{unique}")
        Err(code) =>
          println("letterswitch: Hello 握手失败，错误码 \{code}")
      }
      match server.request_name(service_name, 0) {
        Ok(_) => println("letterswitch: 已申请名称 \{service_name}")
        Err(code) =>
          println(
            "letterswitch: 申请名称 \{service_name} 失败，错误码 \{code}；KWin 将无法调用本服务",
          )
      }
      let session = @core.Session::new()
      println("letterswitch: 就绪，对象路径 \{object_path}")
      server.serve(fn(
        _server : @dbus.Server,
        ctx : @dbus.DispatchCtx,
      ) -> @dbus.Reply? {
        Some(dispatch(session, ctx))
      })
    }
  }
}
