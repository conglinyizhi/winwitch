# WinWitch · 常用操作
#
# 这些步骤踩过坑，别手敲：
#   - 改 QML 后必须重启浮层进程（它是独立进程，不必重启 plasmashell）
#   - 改 KWin 脚本必须开关一次插件才算重载，reconfigure 不管用
#   - 清构建后重来要用 clean，增量缓存有时会掩盖接口变化

SHELL := /bin/bash
REPO  := $(patsubst %/,%,$(dir $(abspath $(lastword $(MAKEFILE_LIST)))))

.DEFAULT_GOAL := help

.PHONY: help
help: ## 显示可用目标
	@grep -hE '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) \
		| awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}'

.PHONY: check
check: ## 静态检查（lint + 语法 + moon check）
	@bash $(REPO)/scripts/check.sh

.PHONY: test
test: ## 跑 MoonBit 单元测试
	@cd $(REPO) && moon test --target wasm-gc

.PHONY: build
build: ## 编译 native helper（release）
	@cd $(REPO) && moon build cmd/main --target native --release

.PHONY: fmt
fmt: ## 格式化 MoonBit 源码
	@cd $(REPO) && moon fmt

.PHONY: info
info: ## 重新生成接口文件并查看公开 API 变化
	@cd $(REPO) && moon info --target native && git --no-pager diff --stat -- '*.mbti'

.PHONY: clean
clean: ## 清掉构建产物与依赖缓存
	@cd $(REPO) && moon clean || true
	@rm -rf $(REPO)/_build
	@echo "已清理构建产物"

.PHONY: ci
ci: check test build ## 提交前完整校验

.PHONY: install
install: ## 安装到用户目录（helper + KWin 脚本 + 浮层 + 自启动）
	@bash $(REPO)/scripts/install.sh

.PHONY: reload
reload: ## 重装并重启 helper/浮层，跑一次冒烟测试
	@bash $(REPO)/scripts/reload.sh

.PHONY: uninstall
uninstall: ## 卸载
	@bash $(REPO)/scripts/uninstall.sh

.PHONY: cancel
cancel: ## 撤销当前选择模式（没有自动超时，卡住时用这个）
	@token=$$(timeout 8 qdbus6 io.github.conglinyizhi.winwitch /LetterSwitch \
		io.github.conglinyizhi.winwitch.Status 2>/dev/null | head -1 | sed 's/^selecting://; s/:.*//'); \
	if [ -z "$$token" ] || [ "$$token" = "idle" ]; then \
		echo "当前不在选择模式"; \
	else \
		timeout 8 qdbus6 io.github.conglinyizhi.winwitch /LetterSwitch \
			io.github.conglinyizhi.winwitch.Cancel "$$token" && echo "已撤销 $$token"; \
	fi

.PHONY: status
status: ## 查看当前状态：进程、顺序源、D-Bus 状态
	@echo "== 进程 =="
	@pgrep -x winwitch -a || echo "  helper 未运行"
	@pgrep -x qml -a | grep winwitch/overlay || echo "  浮层未运行"
	@echo "== D-Bus =="
	@timeout 8 qdbus6 io.github.conglinyizhi.winwitch /LetterSwitch \
		io.github.conglinyizhi.winwitch.Status 2>&1 | head -1 | cut -c1-60 || echo "  查询失败"
	@echo "== KWin 脚本 =="
	@timeout 8 qdbus6 org.kde.KWin /Scripting \
		org.kde.kwin.Scripting.isScriptLoaded winwitch 2>&1
	@echo "== 面板 =="
	@timeout 10 qdbus6 org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript \
		"$$(cat $(REPO)/scripts/panel-status.js)" 2>&1 | tail -1 || echo "  plasmashell 不可达"
	@echo "== 日志尾部 =="
	@tail -5 /tmp/winwitch.log 2>/dev/null | tr -d '\000' || echo "  无日志"
