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
