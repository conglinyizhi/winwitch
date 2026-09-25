///|
/// D-Bus 自省 XML。
///
/// 这个不能省。Qt 系客户端（qdbus6、KDE 里的 Qt 程序）在调用方法前会先请求
/// `org.freedesktop.DBus.Introspectable.Introspect` 来解析参数签名。若服务端
/// 对这种请求不回包，客户端会一直等下去——表现出来是「调用挂死」，而不是报错，
/// 排查时很容易误判成服务端没收到消息。
pub fn introspection_xml() -> String {
  let xml =
    #|<node>
    #|  <interface name="org.clyzhi.LetterSwitch">
    #|    <method name="Begin">
    #|      <arg name="windows" type="s" direction="in"/>
    #|      <arg name="assignment" type="s" direction="out"/>
    #|    </method>
    #|    <method name="Key">
    #|      <arg name="token_and_key" type="s" direction="in"/>
    #|      <arg name="action" type="s" direction="out"/>
    #|    </method>
    #|    <method name="Cancel">
    #|      <arg name="token" type="s" direction="in"/>
    #|      <arg name="result" type="s" direction="out"/>
    #|    </method>
    #|    <method name="Status">
    #|      <arg name="state" type="s" direction="out"/>
    #|    </method>
    #|  </interface>
    #|  <interface name="org.freedesktop.DBus.Introspectable">
    #|    <method name="Introspect">
    #|      <arg name="xml_data" type="s" direction="out"/>
    #|    </method>
    #|  </interface>
    #|  <interface name="org.freedesktop.DBus.Peer">
    #|    <method name="Ping"/>
    #|  </interface>
    #|</node>
    #|
  xml
}

///|
/// 服务对外暴露的方法名。自省 XML 与分发逻辑都以此为准，避免两边写岔。
pub fn method_names() -> Array[String] {
  ["Begin", "Key", "Cancel", "Status"]
}
