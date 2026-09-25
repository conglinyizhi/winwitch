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
  mut slots : Array[Slot]
  mut pending : String
  mut config : String
}

///|
pub fn Session::new() -> Session {
  {
    phase: Idle,
    token: "t0",
    next_token: 1,
    labels: [],
    tasks: [],
    slots: [],
    pending: "",
    config: "",
  }
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
  if self.slots.length() > 0 {
    self.relabel_by_slots(self.slots, alphabet)
  }
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
  // 界面给过首选顺序（任务栏顺序）就按它排；KWin 的枚举顺序与任务栏不一致。
  if self.slots.length() > 0 {
    self.relabel_by_slots(self.slots, alphabet)
  }
  self.labels
}

///|
/// 按给定顺序重排字母。
///
/// 用于「字母顺序跟随任务栏」：面板组件把任务栏顺序（窗口 ID）发过来，据此重排。
/// - 只保留仍在当前会话里的窗口；
/// - 未出现在 `order` 里的窗口按原有相对顺序补在后面，不会丢；
/// - 空列表时保持原样。
pub fn Session::reorder(
  self : Session,
  order : Array[String],
  alphabet? : String = default_alphabet,
) -> Array[Label] {
  let present : Array[String] = []
  for l in self.labels {
    present.push(l.window_id)
  }
  let ordered : Array[String] = []
  for id in order {
    if present.contains(id) && !ordered.contains(id) {
      ordered.push(id)
    }
  }
  for id in present {
    if !ordered.contains(id) {
      ordered.push(id)
    }
  }
  if ordered.length() > 0 {
    self.labels = assign_labels(ordered, alphabet~)
  }
  self.labels
}

///|
/// 记住界面给出的首选顺序；若当前正在选择，立即生效。
pub fn Session::set_preferred_order(
  self : Session,
  order : Array[String],
  alphabet? : String = default_alphabet,
) -> Array[Label] {
  let slots : Array[Slot] = []
  for id in order {
    slots.push({ ids: [id], app_name: "", icon_name: "", title: "", })
  }
  self.set_slots(slots, alphabet~)
}

///|
/// 判断某个窗口是否已经分配了字母。
fn label_exists(labels : Array[Label], id : String) -> Bool {
  for l in labels {
    if l.window_id == id {
      return true
    }
  }
  false
}

///|
/// 按任务栏位置重排字母。
///
/// 每个位置依次占用一个字母：位置里没有窗口（启动器、常驻图标）就空掉一个字母，
/// 位置里有多个窗口（分组）就连续占用多个字母。这样字母与图标的相对位置一致；
/// 若把启动器行直接跳过，后面所有字母都会相对图标整体前移（实测会被用户认为「乱套」）。
fn Session::relabel_by_slots(
  self : Session,
  slots : Array[Slot],
  alphabet : String,
) -> Unit {
  let present : Array[String] = []
  for l in self.labels {
    present.push(l.window_id)
  }
  let out : Array[Label] = []
  let mut slot_index = 0
  for slot in slots {
    if slot_index >= alphabet.length() {
      break
    }
    if slot.ids.length() == 0 {
      // 占位：消耗一个字母，但不产生标签
      slot_index = slot_index + 1
      continue
    }
    for id in slot.ids {
      if slot_index >= alphabet.length() {
        break
      }
      if present.contains(id) && !label_exists(out, id) {
        match alphabet.get_char(slot_index) {
          Some(ch) => out.push({ letter: ch.to_string(), window_id: id, })
          None => ()
        }
        slot_index = slot_index + 1
      }
    }
  }
  // 槽位里没提到的窗口补在后面，一个都不丢
  for id in present {
    if slot_index >= alphabet.length() {
      break
    }
    if !label_exists(out, id) {
      match alphabet.get_char(slot_index) {
        Some(ch) => out.push({ letter: ch.to_string(), window_id: id, })
        None => ()
      }
      slot_index = slot_index + 1
    }
  }
  if out.length() > 0 {
    self.labels = out
  }
}

///|
/// 记住面板推来的任务栏槽位；若当前正在选择，立即重排字母。
pub fn Session::set_slots(
  self : Session,
  slots : Array[Slot],
  alphabet? : String = default_alphabet,
) -> Array[Label] {
  self.slots = slots
  if self.phase is Selecting {
    self.relabel_by_slots(slots, alphabet)
  }
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
      // 记下待激活的窗口：本轮选择可能是界面点的，也可能是键盘按的。
      // 浮层不能直接激活窗口（KWin 也没暴露按 UUID 激活的接口），
      // 所以要留在这里等 KWin 来取。
      self.pending = wid
      self.clear()
      Activate(wid)
    }
    None => Ignore
  }
}

///|
/// 记住界面推来的配置串（`键=值;键=值`）。
///
/// 配置在面板组件那一侧，而浮层是独立进程读不到，所以借 helper 中转：
/// 顺序源把配置推过来，快照末尾以 `@config=` 行带出去。
pub fn Session::set_config(self : Session, text : String) -> Unit {
  self.config = sanitize_field(text, max_len=200)
}

///|
/// 读回当前配置串。
pub fn Session::settings(self : Session) -> String {
  self.config
}

///|
/// 取走待激活的窗口（取完即清）。KWin 只负责「取回来并激活」。
pub fn Session::take_pending(self : Session) -> String? {
  if self.pending == "" {
    None
  } else {
    let id = self.pending
    self.pending = ""
    Some(id)
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
  let with_config = if self.config == "" {
    head
  } else {
    head + "\n@config=" + self.config
  }
  if self.phase is Idle || self.labels.length() == 0 || self.tasks.length() == 0 {
    with_config
  } else {
    with_config + "\n" + encode_detail_full(self.labels, self.tasks, self.slots)
  }
}
