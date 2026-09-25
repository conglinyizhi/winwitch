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
