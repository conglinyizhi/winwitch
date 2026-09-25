// 从面板上移除本项目的组件（如果装过）。
// 字母切窗现在走独立浮层进程，面板不该再占位置。
var panelsList = panels();
var removed = [];
for (var i = 0; i < panelsList.length; i++) {
    var p = panelsList[i];
    for (var j = 0; j < p.widgetIds.length; j++) {
        var a = p.widgetById(p.widgetIds[j]);
        if (a && String(a.type).indexOf("letterswitch") >= 0) {
            removed.push(a.id);
            a.remove();
        }
    }
}
print("letterswitch: 已从面板移除 " + (removed.length ? removed.join(",") : "（无）"));
