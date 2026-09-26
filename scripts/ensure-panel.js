// SPDX-FileCopyrightText: 2026 conglinyizhi <conglinyizhi@qq.com>
// SPDX-License-Identifier: GPL-3.0-or-later

// 确保面板上有「顺序源」组件，且没有本项目的其它旧组件。
//
// 顺序源必须是面板组件：只有 plasmashell 进程内的 QML 能读任务模型
// （独立进程一实例化 TasksModel 就加载失败），而它读到的 WinIdList
// 与 KWin internalId 一致，是让字母对齐任务栏的唯一途径。
var TARGET = "io.github.conglinyizhi.winwitch.panel";
var panelsList = panels();
var found = false;
var removed = [];

for (var i = 0; i < panelsList.length; i++) {
    var p = panelsList[i];
    for (var j = 0; j < p.widgetIds.length; j++) {
        var a = p.widgetById(p.widgetIds[j]);
        if (!a) {
            continue;
        }
        var type = String(a.type);
        // 同时认旧名，改名后旧实例要能被收掉
        if (type.indexOf("winwitch") < 0 && type.indexOf("letterswitch") < 0) {
            continue;
        }
        if (type === TARGET) {
            found = true;
        } else {
            removed.push(a.id);
            a.remove();
        }
    }
}

print("winwitch: 已移除旧组件 " + (removed.length ? removed.join(",") : "（无）"));

if (found) {
    print("winwitch: 顺序源已在面板上");
} else if (panelsList.length === 0) {
    print("winwitch: 没有面板，无法加入顺序源");
} else {
    var w = panelsList[0].addWidget(TARGET);
    print("winwitch: 已加入顺序源 id=" + w.id);
}
