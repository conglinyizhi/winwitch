///|
/// 一个窗口的元信息。标题与应用标识由 KWin 侧提供，用来在界面上说明
/// 「这个字母对应哪个窗口」。
pub(all) struct TaskMeta {
  id : String
  title : String
  app_id : String
} derive(Debug, Eq)

///|
/// 默认字母表顺序：先主行，再上排，最后下排。
/// 手指移动距离短，且刚好 26 个字母。
pub let default_alphabet : String = "ASDFGHJKLQWERTYUIOPZXCVBNM"

///|
/// 一个「字母 -> 窗口」的分配。
pub(all) struct Label {
  letter : String
  window_id : String
} derive(Debug, Eq)

///|
/// 清洗单个字段：制表符与换行会破坏行协议（`id\ttitle\tapp_id`），统一换成空格；
/// 过长则截断，避免状态字符串无限膨胀。
pub fn sanitize_field(text : String, max_len? : Int = 60) -> String {
  let mut out = ""
  let mut i = 0
  let n = text.length()
  while i < n && i < max_len {
    match text.get_char(i) {
      Some(c) =>
        if c == '\t' || c == '\n' || c == '\r' {
          out = out + " "
        } else {
          out = out + c.to_string()
        }
      None => ()
    }
    i = i + 1
  }
  out
}

///|
/// 解析 KWin 传来的任务列表：每行 `id\ttitle\tapp_id`，行与行之间用换行分隔。
/// 少于两列的行走丢弃；标题与应用标识允许为空。
pub fn parse_tasks(text : String) -> Array[TaskMeta] {
  let out : Array[TaskMeta] = []
  for line in split_char(text, '\n') {
    if line != "" {
      let parts = split_char(line, '\t')
      if parts.length() >= 2 {
        let id = sanitize_field(parts[0])
        if id != "" {
          let title = sanitize_field(parts[1])
          let app_id = if parts.length() >= 3 {
            sanitize_field(parts[2])
          } else {
            ""
          }
          out.push({ id, title, app_id, })
        }
      }
    }
  }
  out
}

///|
/// 按 ID 找窗口元信息。
pub fn find_task(tasks : Array[TaskMeta], id : String) -> TaskMeta? {
  for t in tasks {
    if t.id == id {
      return Some(t)
    }
  }
  None
}

///|
/// 编码给界面看的明细：每行 `字母\ttitle\tapp_id`，顺序与字母分配一致。
/// 找不到对应任务时标题留空，界面仍会显示该字母。
pub fn encode_detail(labels : Array[Label], tasks : Array[TaskMeta]) -> String {
  let mut out = ""
  let mut first = true
  for label in labels {
    if !first {
      out = out + "\n"
    }
    first = false
    out = out + label.letter + "\t"
    match find_task(tasks, label.window_id) {
      Some(task) => out = out + task.title + "\t" + task.app_id
      None => out = out + "\t"
    }
  }
  out
}

///|
/// 按任务栏顺序把字母分配给窗口。
///
/// - 空窗口 ID 跳过；
/// - 重复窗口 ID 只取第一次出现；
/// - 分配数量以字母表长度封顶。
pub fn assign_labels(
  windows : Array[String],
  alphabet? : String = default_alphabet,
) -> Array[Label] {
  let out : Array[Label] = []
  let seen : Array[String] = []
  let mut i = 0
  let mut slot = 0
  while i < windows.length() && slot < alphabet.length() {
    let wid = windows[i]
    i = i + 1
    if wid == "" || seen.contains(wid) {
      continue
    }
    match alphabet.get_char(slot) {
      None => break
      Some(ch) => {
        seen.push(wid)
        out.push({ letter: ch.to_string(), window_id: wid, })
        slot = slot + 1
      }
    }
  }
  out
}

///|
/// 查字母对应的窗口。字母统一按大写比较。
pub fn lookup_label(labels : Array[Label], letter : String) -> String? {
  let needle = letter.to_upper()
  for l in labels {
    if l.letter == needle {
      return Some(l.window_id)
    }
  }
  None
}

///|
/// 把分配结果编码成一行，便于跨进程传递。
/// 格式：`A=窗口ID\tS=窗口ID`，只含制表符分隔，不含换行。
pub fn encode_labels(labels : Array[Label]) -> String {
  let mut out = ""
  for i in 0..<labels.length() {
    if i > 0 {
      out = out + "\t"
    }
    out = out + labels[i].letter + "=" + labels[i].window_id
  }
  out
}

///|
/// 解析 `encode_labels` 的输出。空串解析为空数组。
/// 缺少 `=` 或窗口 ID 为空的分片会被丢弃。
pub fn decode_labels(text : String) -> Array[Label] {
  let out : Array[Label] = []
  for part in split_char(text, '\t') {
    if part == "" {
      continue
    }
    match split_once(part, '=') {
      Some((letter, wid)) =>
        if letter != "" && wid != "" {
          out.push({ letter, window_id: wid, })
        }
      None => ()
    }
  }
  out
}

///|
/// 按单个字符切分，保留空片段。
pub fn split_char(text : String, sep : Char) -> Array[String] {
  let out : Array[String] = []
  let mut cur = ""
  for i in 0..<text.length() {
    match text.get_char(i) {
      Some(c) =>
        if c == sep {
          out.push(cur)
          cur = ""
        } else {
          cur = cur + c.to_string()
        }
      None => ()
    }
  }
  out.push(cur)
  out
}

///|
/// 按第一个分隔符切一次。找不到分隔符时返回 None。
pub fn split_once(text : String, sep : Char) -> (String, String)? {
  let mut idx = -1
  let mut i = 0
  let n = text.length()
  while i < n {
    if text.get_char(i) == Some(sep) {
      idx = i
      break
    }
    i = i + 1
  }
  if idx < 0 {
    return None
  }
  let mut left = ""
  for j in 0..<idx {
    match text.get_char(j) {
      Some(c) => left = left + c.to_string()
      None => ()
    }
  }
  let mut right = ""
  for k in (idx + 1)..<n {
    match text.get_char(k) {
      Some(c) => right = right + c.to_string()
      None => ()
    }
  }
  Some((left, right))
}

///|
/// 任务栏上的一个位置（一个图标）。
///
/// 分组时一个图标对应多个窗口；启动器（常驻图标）没有窗口，但它**占一个位置**——
/// 必须占位，否则后面所有字母都会相对图标错开一位。
pub(all) struct Slot {
  ids : Array[String]
  app_name : String
  icon_name : String
  title : String
} derive(Debug, Eq)

///|
/// 解析界面推来的任务栏顺序：每行 `<ids 逗号分隔>\t应用名\t图标名\t标题`。
/// ids 为空的行表示这个图标没有窗口（启动器），仍占一个字母位。
pub fn parse_slots(text : String) -> Array[Slot] {
  let out : Array[Slot] = []
  for line in split_char(text, '\n') {
    if line != "" {
      let parts = split_char(line, '\t')
      let ids : Array[String] = []
      if parts.length() >= 1 {
        for id in split_char(parts[0], ',') {
          let clean = sanitize_field(id)
          if clean != "" {
            ids.push(clean)
          }
        }
      }
      let app_name = if parts.length() >= 2 {
        sanitize_field(parts[1], max_len=40)
      } else {
        ""
      }
      let icon_name = if parts.length() >= 3 {
        sanitize_field(parts[2], max_len=60)
      } else {
        ""
      }
      let title = if parts.length() >= 4 {
        sanitize_field(parts[3])
      } else {
        ""
      }
      out.push({ ids, app_name, icon_name, title, })
    }
  }
  out
}

///|
/// 编码槽位（调试与测试用）。
pub fn encode_slots(slots : Array[Slot]) -> String {
  let mut out = ""
  let mut first = true
  for slot in slots {
    if !first {
      out = out + "\n"
    }
    first = false
    let mut ids = ""
    for i in 0..<slot.ids.length() {
      if i > 0 {
        ids = ids + ","
      }
      ids = ids + slot.ids[i]
    }
    out = out +
      ids +
      "\t" +
      slot.app_name +
      "\t" +
      slot.icon_name +
      "\t" +
      slot.title
  }
  out
}

///|
/// 按槽位查窗口对应的位置。
pub fn find_slot(slots : Array[Slot], id : String) -> Slot? {
  for slot in slots {
    if slot.ids.contains(id) {
      return Some(slot)
    }
  }
  None
}

///|
/// 编码给界面看的明细：每行 `字母\t应用名\t图标名\t标题`，顺序与字母分配一致。
///
/// 应用名与图标名来自面板推来的槽位（任务模型最准），窗口标题优先用 KWin 的
/// （更完整），取不到再退回槽位里的。
pub fn encode_detail_full(
  labels : Array[Label],
  tasks : Array[TaskMeta],
  slots : Array[Slot],
) -> String {
  let mut out = ""
  let mut first = true
  // 启动器槽位（ids 为空）没有窗口 ID，没法按 ID 匹配，只能按顺序认领。
  let empty_slots : Array[Slot] = []
  for s in slots {
    if s.ids.length() == 0 {
      empty_slots.push(s)
    }
  }
  let mut empty_used = 0
  for label in labels {
    if !first {
      out = out + "\n"
    }
    first = false
    let mut app_name = ""
    let mut icon_name = ""
    let mut slot_title = ""
    let mut is_launcher = false
    match find_slot(slots, label.window_id) {
      Some(slot) => {
        app_name = slot.app_name
        icon_name = slot.icon_name
        slot_title = slot.title
      }
      None =>
        // 窗口 ID 为空的字母 = 固定着但没启动的应用，拿一个空槽位的元数据
        if label.window_id == "" && empty_used < empty_slots.length() {
          let s = empty_slots[empty_used]
          empty_used = empty_used + 1
          app_name = s.app_name
          icon_name = s.icon_name
          slot_title = s.title
          is_launcher = true
        }
    }
    let task = find_task(tasks, label.window_id)
    // 窗口标题优先用 KWin 的 caption（真实窗口标题），取不到再退回槽位的展示文本
    let mut title = match task {
      Some(t) => t.title
      None => ""
    }
    if title == "" {
      title = slot_title
    }
    // 应用名兜底：槽位没给就用 KWin 的应用标识
    if app_name == "" {
      match task {
        Some(t) => app_name = t.app_id
        None => ()
      }
    }
    // 第 5 列：1 = 启动器条目（要按两次才启动），空 = 普通窗口
    let launcher_flag = if is_launcher { "1" } else { "" }
    out = out +
      label.letter +
      "\t" +
      app_name +
      "\t" +
      icon_name +
      "\t" +
      title +
      "\t" +
      launcher_flag
  }
  out
}
