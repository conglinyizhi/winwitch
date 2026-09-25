// 报告面板上有几个本项目的组件（顺序源应当恰好一个）。
var panelsList = panels();
var mine = [];
for (var i = 0; i < panelsList.length; i++) {
    var p = panelsList[i];
    for (var j = 0; j < p.widgetIds.length; j++) {
        var a = p.widgetById(p.widgetIds[j]);
        if (a && String(a.type).indexOf("winwitch") >= 0) {
            mine.push(String(a.type) + "#" + a.id);
        }
    }
}
print("winwitch 组件：" + (mine.length ? mine.join(" ") : "（无）"));
