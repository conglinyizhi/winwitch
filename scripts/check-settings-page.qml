// 无头重演 KCM 初始化设置页，专抓「控件在初始化时把配置值冲掉」这类问题。
//
// 为什么需要它：设置页只能人工在 Plasma 里点开，脚本打不开（internalAction 不在
// 桌面脚本 API 里）。结果就是我一直只验得动「能自动化的那半条链路」，坏的偏偏是
// 需要人手点开的那半条——「我这儿好好的，你那儿不行」的根子就在这里。
//
// 做法：像 KCM 那样在创建时把配置值赋给 cfg_ 属性，等一拍再回读，看属性还在不在。
//
// 能力边界（重要，别把它当「设置页已验证」）：
//   它只证明「页面能加载、四个 cfg_ 属性存在、创建后没有被立刻改掉」。
//   当初那个真实故障（ComboBox 抢跑把配置值冲成列表第一项）**复现不出来**：
//   把那段错误代码塞回去，这个检查照样通过（做过反向验证）。原因是 KCM 真实的
//   属性赋值时机与这里的 createObject 不一致，靠 QML 这边模拟不出来。
//   所以设置页的最终确认仍然只能由人点一次，别拿这个绿灯当结论。
//
// 用法（由 scripts/check.sh 调用）：
//     QT_QPA_PLATFORM=offscreen qml6 scripts/check-settings-page.qml
// 退出码非 0 表示有问题。
import QtQuick

// 根对象必须是可见窗口，否则 qml 工具会「Did not load any objects」直接退出，
// 定时器根本轮不到跑。offscreen 平台下这个窗口不会真的显示。
Window {
    id: harness

    visible: true
    width: 1
    height: 1

    property var page: null
    property var failures: []

    function fail(text) {
        harness.failures.push(text);
        console.log("  不合规：" + text);
    }

    function expect(name, expected) {
        var actual = harness.page[name];
        if (String(actual) !== String(expected)) {
            harness.fail(name + " 被控件冲掉了：期望 " + expected + "，实际 " + actual);
        }
    }

    Component.onCompleted: {
        var comp = Qt.createComponent("../panel/contents/ui/configGeneral.qml");
        if (comp.status !== Component.Ready) {
            harness.fail("设置页加载失败：" + comp.errorString());
            Qt.exit(1);
            return;
        }

        harness.page = comp.createObject(null, {
            "cfg_overlayPosition": "top",
            "cfg_maxColumns": 3,
            "cfg_showWindowTitle": false,
            "cfg_backgroundStyle": "opaque"
        });
        if (harness.page === null) {
            harness.fail("设置页创建失败：" + comp.errorString());
            Qt.exit(1);
            return;
        }

        settle.start();
    }

    Timer {
        id: settle

        interval: 120
        repeat: false
        onTriggered: {
            harness.expect("cfg_overlayPosition", "top");
            harness.expect("cfg_maxColumns", 3);
            harness.expect("cfg_showWindowTitle", false);
            harness.expect("cfg_backgroundStyle", "opaque");
            Qt.exit(harness.failures.length > 0 ? 1 : 0);
        }
    }

    // 兜底：万一哪里卡住，别把检查脚本挂死
    Timer {
        interval: 6000
        running: true
        onTriggered: {
            harness.fail("检查超时：设置页没有走到稳定状态");
            Qt.exit(1);
        }
    }
}
