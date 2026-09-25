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
