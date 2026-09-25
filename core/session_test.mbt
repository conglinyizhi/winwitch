///|
test "新会话处于空闲" {
  let session = @core.Session::new()
  assert_false(session.is_selecting())
  assert_eq(session.encode(), "idle:t0")
}

///|
test "开始选择后分配标签并启用新 token" {
  let session = @core.Session::new()
  let labels = session.begin(["w1", "w2"])
  assert_true(session.is_selecting())
  assert_eq(labels.length(), 2)
  assert_eq(session.token(), "t1")
  assert_eq(session.encode(), "selecting:t1:A=w1\tS=w2")
}

///|
test "空闲状态下按键一律忽略" {
  let session = @core.Session::new()
  assert_eq(session.handle_key("t0", "A"), @core.Ignore)
  assert_eq(session.handle_key("t0", "Escape"), @core.Ignore)
  assert_eq(session.encode(), "idle:t0")
}

///|
test "按有效字母激活对应窗口并退出选择" {
  let session = @core.Session::new()
  ignore(session.begin(["w1", "w2", "w3"]))
  assert_eq(session.handle_key(session.token(), "D"), @core.Activate("w3"))
  assert_false(session.is_selecting())
}

///|
test "小写字母同样可以激活" {
  let session = @core.Session::new()
  ignore(session.begin(["w1", "w2"]))
  assert_eq(session.handle_key(session.token(), "s"), @core.Activate("w2"))
}

///|
test "Esc 取消且不激活任何窗口" {
  let session = @core.Session::new()
  ignore(session.begin(["w1", "w2"]))
  assert_eq(session.handle_key(session.token(), "Escape"), @core.Cancel)
  assert_false(session.is_selecting())
  assert_eq(session.labels().length(), 0)
}

///|
test "Esc 在映射为空时仍然可以退出" {
  let session = @core.Session::new()
  ignore(session.begin([]))
  let token = session.token()
  assert_true(session.is_selecting())
  assert_eq(session.handle_key(token, "Escape"), @core.Cancel)
  assert_false(session.is_selecting())
}

///|
test "Esc 拼写 Esc 也按取消处理" {
  let session = @core.Session::new()
  ignore(session.begin(["w1"]))
  assert_eq(session.handle_key(session.token(), "Esc"), @core.Cancel)
  assert_false(session.is_selecting())
}

///|
test "Esc 优先于字母匹配" {
  let session = @core.Session::new()
  ignore(session.begin(["w1"]))
  ignore(session.handle_key(session.token(), "A"))
  ignore(session.begin(["w2"]))
  assert_eq(session.handle_key(session.token(), "Escape"), @core.Cancel)
  assert_eq(session.labels().length(), 0)
}

///|
test "未分配的字母不改变会话状态" {
  let session = @core.Session::new()
  ignore(session.begin(["w1"]))
  let token = session.token()
  assert_eq(session.handle_key(token, "Z"), @core.Ignore)
  assert_true(session.is_selecting())
  assert_eq(session.token(), token)
}

///|
test "陈旧 token 的按键被忽略" {
  let session = @core.Session::new()
  ignore(session.begin(["w1"]))
  let stale = session.token()
  session.clear()
  ignore(session.begin(["w2"]))
  assert_eq(session.handle_key(stale, "A"), @core.Ignore)
  assert_true(session.is_selecting())
  assert_eq(session.labels()[0].window_id, "w2")
}

///|
test "超时在会话内生效并清空标签" {
  let session = @core.Session::new()
  ignore(session.begin(["w1"]))
  assert_eq(session.handle_timeout(session.token()), @core.Timeout)
  assert_false(session.is_selecting())
  assert_eq(session.labels().length(), 0)
}

///|
test "陈旧超时不会退出新会话" {
  let session = @core.Session::new()
  ignore(session.begin(["w1"]))
  let stale = session.token()
  session.clear()
  ignore(session.begin(["w2"]))
  assert_eq(session.handle_timeout(stale), @core.Ignore)
  assert_true(session.is_selecting())
}

///|
test "空闲时的超时被忽略" {
  let session = @core.Session::new()
  assert_eq(session.handle_timeout("t0"), @core.Ignore)
}

///|
test "每次进入或退出都会更换 token" {
  let session = @core.Session::new()
  ignore(session.begin(["w1"]))
  let first = session.token()
  session.clear()
  let second = session.token()
  ignore(session.begin(["w1"]))
  let third = session.token()
  assert_true(first != second)
  assert_true(second != third)
}

///|
test "显式取消与 Esc 等价" {
  let session = @core.Session::new()
  ignore(session.begin(["w1", "w2"]))
  assert_eq(session.handle_cancel(session.token()), @core.Cancel)
  assert_false(session.is_selecting())
  assert_eq(session.labels().length(), 0)
}

///|
test "陈旧 token 的取消被忽略" {
  let session = @core.Session::new()
  ignore(session.begin(["w1"]))
  let stale = session.token()
  session.clear()
  ignore(session.begin(["w2"]))
  assert_eq(session.handle_cancel(stale), @core.Ignore)
  assert_true(session.is_selecting())
}

///|
test "空闲时的取消被忽略" {
  let session = @core.Session::new()
  assert_eq(session.handle_cancel("t0"), @core.Ignore)
}

///|
test "begin_tasks 记住标题并出现在快照里" {
  let session = @core.Session::new()
  let tasks = @core.parse_tasks("w1\t编辑器\tkate\nw2\t浏览器\tfirefox")
  let labels = session.begin_tasks(tasks)
  assert_eq(labels.length(), 2)
  // 明细格式：字母、应用名、图标名、窗口标题。
  // 没有槽位时应用名退回 KWin 的应用标识，图标名留空。
  assert_eq(
    session.snapshot(),
    "selecting:t1:A=w1\tS=w2\nA\tkate\t\t编辑器\nS\tfirefox\t\t浏览器",
  )
}

///|
test "只有 ID 时快照仍然只有一行" {
  let session = @core.Session::new()
  ignore(session.begin(["w1", "w2"]))
  // begin 走的是无标题路径，不应多出明细行
  assert_eq(session.snapshot(), "selecting:t1:A=w1\tS=w2")
}

///|
test "空闲时快照只有状态行" {
  let session = @core.Session::new()
  assert_eq(session.snapshot(), "idle:t0")
}

///|
test "取消后快照回到空闲且不留明细" {
  let session = @core.Session::new()
  let tasks = @core.parse_tasks("w1\t编辑器\tkate")
  ignore(session.begin_tasks(tasks))
  session.clear()
  assert_eq(session.snapshot(), "idle:t2")
}

///|
test "首选顺序可以把任务栏顺序套到字母上" {
  let session = @core.Session::new()
  ignore(session.begin(["kwin1", "kwin2", "kwin3"]))
  // 任务栏顺序是 3、1、2
  ignore(session.set_preferred_order(["kwin3", "kwin1", "kwin2"]))
  let labels = session.labels()
  assert_eq(labels[0].window_id, "kwin3")
  assert_eq(labels[1].window_id, "kwin1")
  assert_eq(labels[2].window_id, "kwin2")
  assert_eq(labels[0].letter, "A")
}

///|
test "首选顺序里没有的窗口补在后面不丢" {
  let session = @core.Session::new()
  ignore(session.begin(["w1", "w2", "w3"]))
  ignore(session.set_preferred_order(["w3"]))
  let labels = session.labels()
  assert_eq(labels.length(), 3)
  assert_eq(labels[0].window_id, "w3")
  // 其余两个保持原有相对顺序
  assert_eq(labels[1].window_id, "w1")
  assert_eq(labels[2].window_id, "w2")
}

///|
test "首选顺序里的陌生窗口被忽略" {
  let session = @core.Session::new()
  ignore(session.begin(["w1", "w2"]))
  ignore(session.set_preferred_order(["不存在", "w2", "w1"]))
  let labels = session.labels()
  assert_eq(labels.length(), 2)
  assert_eq(labels[0].window_id, "w2")
  assert_eq(labels[1].window_id, "w1")
}

///|
test "空闲时设置首选顺序不产生标签" {
  let session = @core.Session::new()
  let labels = session.set_preferred_order(["w1"])
  assert_eq(labels.length(), 0)
  assert_eq(session.snapshot(), "idle:t0")
}

///|
test "首选顺序在下次开始时自动生效" {
  let session = @core.Session::new()
  ignore(session.set_preferred_order(["b", "a"]))
  ignore(session.begin(["a", "b"]))
  let labels = session.labels()
  assert_eq(labels[0].window_id, "b")
  assert_eq(labels[1].window_id, "a")
}

///|
test "启动器位置会空掉一个字母，保证后面与图标对齐" {
  let session = @core.Session::new()
  // 任务栏：两个常驻图标在前，然后是 w1、w2
  let slots = @core.parse_slots("\t启动器A\tapp-a\t\n\t启动器B\tapp-b\t\nw1\t编辑器\tkate\t\nw2\t浏览器\tfirefox\t")
  ignore(session.begin(["w1", "w2"]))
  ignore(session.set_slots(slots))
  let labels = session.labels()
  // 前两个位置空掉 A、S，w1 拿 D，w2 拿 F
  assert_eq(labels[0].letter, "D")
  assert_eq(labels[0].window_id, "w1")
  assert_eq(labels[1].letter, "F")
  assert_eq(labels[1].window_id, "w2")
}

///|
test "快照带出应用名与图标名" {
  let session = @core.Session::new()
  let slots = @core.parse_slots("w1\t飞书\tfeishu\t飞书聊天窗口")
  ignore(session.begin_tasks(@core.parse_tasks("w1\t窗口标题\tFeishu")))
  ignore(session.set_slots(slots))
  assert_eq(session.snapshot(), "selecting:t1:A=w1\nA\t飞书\tfeishu\t窗口标题")
}

///|
test "分组图标里的多个窗口连续占字母" {
  let session = @core.Session::new()
  let slots = @core.parse_slots("w1,w2\t编辑器\tkate\t\nw3\t浏览器\tfirefox\t")
  ignore(session.begin(["w1", "w2", "w3"]))
  ignore(session.set_slots(slots))
  let labels = session.labels()
  assert_eq(labels[0].letter, "A")
  assert_eq(labels[1].letter, "S")
  assert_eq(labels[2].letter, "D")
  assert_eq(labels[0].window_id, "w1")
  assert_eq(labels[1].window_id, "w2")
  assert_eq(labels[2].window_id, "w3")
}
