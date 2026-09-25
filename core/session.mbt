///|
/// 会话阶段。只有两个状态，任何其它状态都是 bug。
pub(all) enum Phase {
  Idle
  Selecting
} derive(Debug, Eq)

///|
/// 对一次输入的处理结果。
pub(all) enum Action {
  /// 激活指定窗口，随后退出选择模式。
  Activate(String)
  /// 取消：不激活任何窗口。
  Cancel
  /// 超时退出。
  Timeout
  /// 不认识、不属于当前会话，或处于空闲：什么都不做。
  Ignore
} derive(Debug, Eq)

///|
/// 选择会话。
///
/// `token` 用于丢弃陈旧事件：每次进入或退出选择模式都会换一个新 token，
/// 旧快捷键、旧 helper 或迟到的超时都不会误操作新一批窗口。
///
/// token 故意用字符串表示：整套 IPC 因此只传字符串，两端都不需要解析整数。
pub(all) struct Session {
  mut phase : Phase
  mut token : String
  mut next_token : Int
  mut labels : Array[Label]
  mut tasks : Array[TaskMeta]
}

///|
pub fn Session::new() -> Session {
  { phase: Idle, token: "t0", next_token: 1, labels: [], tasks: [] }
}

///|
pub fn Session::is_selecting(self : Session) -> Bool {
  self.phase is Selecting
}

///|
pub fn Session::token(self : Session) -> String {
  self.token
}

///|
pub fn Session::labels(self : Session) -> Array[Label] {
  self.labels
}

///|
fn Session::rotate_token(self : Session) -> Unit {
  self.token = "t" + self.next_token.to_string()
  self.next_token = self.next_token + 1
}

///|
/// 进入选择模式：分配字母并启用新 token。
pub fn Session::begin(
  self : Session,
  windows : Array[String],
  alphabet? : String = default_alphabet,
) -> Array[Label] {
  self.rotate_token()
  self.labels = assign_labels(windows, alphabet~)
  // 这条路径只有 ID，没有标题；不要留下 tasks，否则快照会多出空明细行。
  self.tasks = []
  self.phase = Selecting
  self.labels
}

///|
/// 进入选择模式，同时记住窗口的标题与应用标识，供界面说明字母对应哪个窗口。
pub fn Session::begin_tasks(
  self : Session,
  tasks : Array[TaskMeta],
  alphabet? : String = default_alphabet,
) -> Array[Label] {
  self.rotate_token()
  let ids : Array[String] = []
  for t in tasks {
    ids.push(t.id)
  }
  self.labels = assign_labels(ids, alphabet~)
  self.tasks = tasks
  self.phase = Selecting
  self.labels
}

///|
/// 清空状态并作废当前 token。取消与超时都走这里。
pub fn Session::clear(self : Session) -> Unit {
  self.phase = Idle
  self.labels = []
  self.tasks = []
  self.rotate_token()
}

///|
/// 处理一次按键。
///
/// `Escape` 优先于任何字母匹配：即使映射为空、字母表已经用尽，
/// 或者窗口列表刚刚失效，也只会取消，不会激活窗口。
pub fn Session::handle_key(
  self : Session,
  token : String,
  key : String,
) -> Action {
  if token != self.token {
    return Ignore
  }
  if self.phase is Idle {
    return Ignore
  }
  if key == "Escape" || key == "Esc" {
    return self.handle_cancel(token)
  }
  match lookup_label(self.labels, key) {
    Some(wid) => {
      self.clear()
      Activate(wid)
    }
    None => Ignore
  }
}

///|
/// 显式取消。Esc 与宿主发来的取消请求都走这里。
///
/// 语义与 Esc 完全一致：只清理状态并作废 token，不激活任何窗口。
pub fn Session::handle_cancel(self : Session, token : String) -> Action {
  if token != self.token {
    return Ignore
  }
  if self.phase is Idle {
    return Ignore
  }
  self.clear()
  Cancel
}

///|
/// 超时处理。只有属于当前会话的超时才会退出选择模式。
pub fn Session::handle_timeout(self : Session, token : String) -> Action {
  if token != self.token {
    return Ignore
  }
  if self.phase is Idle {
    return Ignore
  }
  self.clear()
  Timeout
}

///|
/// 编码当前状态，供跨进程查询。
/// 空闲时返回 `idle:<token>`；选择中返回 `selecting:<token>:<labels>`。
pub fn Session::encode(self : Session) -> String {
  match self.phase {
    Idle => "idle:" + self.token
    Selecting => "selecting:" + self.token + ":" + encode_labels(self.labels)
  }
}

///|
/// 给界面用的快照：第一行是状态（与 `encode` 一致），其余每行是
/// `字母\ttitle\tapp_id`。界面只需一次查询就能把字母与窗口对应起来。
pub fn Session::snapshot(self : Session) -> String {
  let head = self.encode()
  if self.phase is Idle || self.labels.length() == 0 || self.tasks.length() == 0 {
    head
  } else {
    head + "\n" + encode_detail(self.labels, self.tasks)
  }
}
