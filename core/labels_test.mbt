///|
test "空窗口列表分配不到任何标签" {
  let labels = @core.assign_labels([])
  assert_eq(labels.length(), 0)
}

///|
test "按顺序分配字母" {
  let labels = @core.assign_labels(["w1", "w2", "w3"])
  debug_inspect(
    labels,
    content=(
      #|[
      #|  { letter: "A", window_id: "w1" },
      #|  { letter: "S", window_id: "w2" },
      #|  { letter: "D", window_id: "w3" },
      #|]
    ),
  )
}

///|
test "重复窗口只取第一次出现" {
  let labels = @core.assign_labels(["w1", "w1", "w2"])
  debug_inspect(
    labels,
    content=(
      #|[{ letter: "A", window_id: "w1" }, { letter: "S", window_id: "w2" }]
    ),
  )
}

///|
test "空窗口 ID 被跳过" {
  let labels = @core.assign_labels(["", "w2"])
  debug_inspect(
    labels,
    content=(
      #|[{ letter: "A", window_id: "w2" }]
    ),
  )
}

///|
test "窗口数超过字母表长度时封顶" {
  let windows : Array[String] = []
  for i in 0..<40 {
    windows.push("w\{i}")
  }
  let labels = @core.assign_labels(windows)
  assert_eq(labels.length(), 26)
  assert_eq(labels[25].letter, "M")
  assert_eq(labels[25].window_id, "w25")
}

///|
test "自定义字母表按给定顺序生效" {
  let labels = @core.assign_labels(["w1", "w2", "w3"], alphabet="123")
  debug_inspect(
    labels,
    content=(
      #|[
      #|  { letter: "1", window_id: "w1" },
      #|  { letter: "2", window_id: "w2" },
      #|  { letter: "3", window_id: "w3" },
      #|]
    ),
  )
}

///|
test "按大写字母查窗口" {
  let labels = @core.assign_labels(["w1", "w2"])
  assert_eq(@core.lookup_label(labels, "A"), Some("w1"))
  assert_eq(@core.lookup_label(labels, "S"), Some("w2"))
}

///|
test "字母大小写不敏感" {
  let labels = @core.assign_labels(["w1", "w2"])
  assert_eq(@core.lookup_label(labels, "a"), Some("w1"))
  assert_eq(@core.lookup_label(labels, "s"), Some("w2"))
}

///|
test "未分配的字母查不到窗口" {
  let labels = @core.assign_labels(["w1"])
  assert_eq(@core.lookup_label(labels, "Z"), None)
}

///|
test "多字符输入不匹配任何标签" {
  let labels = @core.assign_labels(["w1", "w2"])
  assert_eq(@core.lookup_label(labels, "AS"), None)
  assert_eq(@core.lookup_label(labels, ""), None)
}

///|
test "编码后解码可还原" {
  let labels = @core.assign_labels(["w1", "w2", "w3"])
  let text = @core.encode_labels(labels)
  assert_eq(text, "A=w1\tS=w2\tD=w3")
  debug_inspect(
    @core.decode_labels(text),
    content=(
      #|[
      #|  { letter: "A", window_id: "w1" },
      #|  { letter: "S", window_id: "w2" },
      #|  { letter: "D", window_id: "w3" },
      #|]
    ),
  )
}

///|
test "解码空串得到空数组" {
  assert_eq(@core.decode_labels("").length(), 0)
}

///|
test "解码丢弃没有等号或窗口为空的片段" {
  let labels = @core.decode_labels("A=w1\tBROKEN\tS=\tD=w4")
  debug_inspect(
    labels,
    content=(
      #|[{ letter: "A", window_id: "w1" }, { letter: "D", window_id: "w4" }]
    ),
  )
}

///|
test "按字符切分保留空片段" {
  debug_inspect(
    @core.split_char("a,,b", ','),
    content=(
      #|["a", "", "b"]
    ),
  )
  debug_inspect(@core.split_char("", ','), content="[\"\"]")
}

///|
test "split_once 在第一个分隔符处切开" {
  assert_eq(@core.split_once("12:A", ':'), Some(("12", "A")))
  assert_eq(@core.split_once("12:A:B", ':'), Some(("12", "A:B")))
  assert_eq(@core.split_once("no-separator", ':'), None)
}

///|
test "窗口 ID 含等号时只按第一个等号切分" {
  let labels = @core.decode_labels("A=app=v1")
  debug_inspect(
    labels,
    content=(
      #|[{ letter: "A", window_id: "app=v1" }]
    ),
  )
}

///|
test "sanitize_field 把制表符与换行换成空格" {
  assert_eq(@core.sanitize_field("a\tb"), "a b")
  assert_eq(@core.sanitize_field("a\nb"), "a b")
  assert_eq(@core.sanitize_field("a\r\nb"), "a  b")
}

///|
test "sanitize_field 按上限截断" {
  assert_eq(@core.sanitize_field("abcdefg", max_len=4), "abcd")
  // 未超过上限时原样返回
  assert_eq(@core.sanitize_field("abc", max_len=10), "abc")
}

///|
test "parse_tasks 解析 id 标题 应用标识" {
  let tasks = @core.parse_tasks("id1\t标题一\tfirefox\nid2\t标题二\tkonsole")
  debug_inspect(
    tasks,
    content=(
      #|[
      #|  { id: "id1", title: "标题一", app_id: "firefox" },
      #|  { id: "id2", title: "标题二", app_id: "konsole" },
      #|]
    ),
  )
}

///|
test "parse_tasks 丢弃列数不足或 ID 为空的行" {
  // 只有一列、空行、ID 为空，都应被丢弃
  let tasks = @core.parse_tasks("只有一列\n\n\t标题但没有ID\nid4\t标题四\tvim")
  debug_inspect(
    tasks,
    content=(
      #|[{ id: "id4", title: "标题四", app_id: "vim" }]

    ),
  )
}

///|
test "parse_tasks 允许缺少应用标识" {
  let tasks = @core.parse_tasks("id1\t标题")
  debug_inspect(
    tasks,
    content=(
      #|[{ id: "id1", title: "标题", app_id: "" }]

    ),
  )
}

///|
test "encode_detail 按字母顺序带出标题与应用标识" {
  let labels = @core.assign_labels(["w1", "w2"])
  let tasks = @core.parse_tasks("w1\t第一个窗口\tfirefox\nw2\t第二个窗口\tkonsole")
  assert_eq(
    @core.encode_detail(labels, tasks),
    "A\t第一个窗口\tfirefox\nS\t第二个窗口\tkonsole",
  )
}

///|
test "encode_detail 找不到窗口时留空但仍占一行" {
  let labels = @core.assign_labels(["w1", "w9"])
  let tasks = @core.parse_tasks("w1\t存在的窗口\tfirefox")
  assert_eq(@core.encode_detail(labels, tasks), "A\t存在的窗口\tfirefox\nS\t\t")
}
