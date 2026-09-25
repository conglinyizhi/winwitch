///|
test "自省 XML 声明了全部对外方法" {
  let xml = @core.introspection_xml()
  for name in @core.method_names() {
    let needle = "<method name=\"" + name + "\">"
    if !xml.contains(needle) {
      fail("自省 XML 缺少方法 \{name}")
    }
  }
}

///|
test "自省 XML 声明了 Qt 客户端依赖的两个公共接口" {
  let xml = @core.introspection_xml()
  assert_true(xml.contains("org.freedesktop.DBus.Introspectable"))
  assert_true(xml.contains("org.freedesktop.DBus.Peer"))
}

///|
test "自省 XML 是完整的 node 文档" {
  let xml = @core.introspection_xml()
  assert_true(xml.contains("<node>"))
  assert_true(xml.contains("</node>"))
  assert_true(xml.contains("io.github.conglinyizhi.winwitch"))
}
