---
name: goenv-manager
description: 使用 goenv 和 pyenv 安装、审计或修复跨平台 Go/Python 版本管理。当需要配置按项目自动切换 Go、检查 Git 版本兼容性，或支持 CentOS 7 等较旧 Linux 时使用。
---

# Go 环境管理

本 skill 用于主机级别的 Go/Python 版本管理配置和修复。修改前必须先检查
主机环境，并保留用户已有的、与本任务无关的 shell 配置。安装顺序、检查项、
shell hook、可选模块设置和验证细则见
[references/operations.md](references/operations.md)。旧系统约束见
[references/compatibility.md](references/compatibility.md)。

## 触发条件

| 场景 | 行为 |
| --- | --- |
| 需要安装或配置 goenv | 检查 Git，按 Git -> pyenv -> goenv 顺序执行 |
| 需要按项目自动切换 Go 版本 | 检查 `.go-version`、`go.mod` 和 shell hook |
| 需要安装或切换 Python 版本 | 使用 pyenv；Python 最低版本为 `3.10` |
| 主机为 CentOS/RHEL 7 或较旧 Linux | 阅读兼容性说明，避免依赖系统目录和新 Bash 语法 |
| Git 不存在或版本不高于 `2.23` | 从源码安装到用户目录后再继续 |
| Python 下载容易超时或卡住 | 使用 `pyenv-install` 并可选配置 `PYENV_INSTALL_MIRRORS` 镜像 |
| 需要检查 Go 扩展插件是否匹配当前 Go 版本 | 使用 `goauto --check-tools` 校验固定插件版本 |
| 通过 SSH 使用 VS Code、Comate 等编辑器，插件找不到 Go 工具 | 检查 login 和 non-interactive 启动文件是否加载 `~/.goenvrc` |

## 核心能力

- 检查 Git、Python、shell、操作系统、内核和 CPU 架构。
- 将 Git、pyenv、goenv、Python 和 Go 工具安装到用户目录。
- 通过 `pyenv-install` 安装 Python，可用 `PYENV_INSTALL_MIRRORS` 指定可选镜像。
- 根据项目中的 `.go-version` 或 `go.mod` 自动切换 Go 版本。
- 按 Go 的 `major.minor` 选择插件版本，并校验二进制内嵌模块版本。
- 按 VS Code Go 扩展推荐清单管理 `gopls`、`dlv`、`goimports`、`gofumpt`、
  `gotests`、`impl`、`goplay` 和 `staticcheck`。
- 将 pyenv、goenv 和用户可执行目录持久写入交互、login 和 non-interactive
  shell 初始化配置，使 SSH 场景下的 VS Code/Comate 看到同一套环境。
- 在 Go 项目根目录维护 `.vscode/settings.json`，让编辑器及其中运行的插件
  使用该项目固定版本的 Go 与插件。
- 可选模块设置：仅当显式设置 `GOENV_GOPROXY`、`GOENV_GOPRIVATE`、
  `GOENV_GONOPROXY`、`GOENV_GONOSUMDB`、`GOENV_GO111MODULE` 时才写入对应
  的 Go 环境，默认不改动 Go 自身配置。

## 工作流程

```text
┌────────────┐     ┌────────────┐     ┌────────────┐
│ 检查主机   │────►│ Git > 2.23 │────►│ 安装 pyenv │
└────────────┘     └────────────┘     └─────┬──────┘
                                            │
                                            ▼
┌────────────┐     ┌────────────┐     ┌────────────┐
│ 校验插件   │◄────│ 模块设置   │◄────│ 安装 goenv │
└─────┬──────┘     └────────────┘     └────────────┘
      │
      ▼
┌────────────┐
│ 验证 shell │
└────────────┘
```

1. 读取已有 shell 配置、PATH、pyenv 和 goenv 状态。
2. 检查 Git 版本；缺失或不满足 `>2.23` 时安装用户级 Git。
3. Git 验证成功后安装或复用 pyenv，并确保 Python `>=3.10`。
4. 安装或复用 goenv，复制自动切换模板。
5. 幂等更新交互、login 和 non-interactive 启动文件，加载 `~/.goenvrc`。
6. 仅当设置 `GOENV_GOPROXY` 等可选变量时，才导出并持久化对应的 Go 模块
   设置；未设置时保持 Go 默认行为。
7. 按 Go `major.minor` 校验推荐插件；缺失或不匹配时重新安装。
8. 验证 bash/zsh 语法、版本命令和项目目录切换行为。

Git、pyenv、goenv 和 Python 编译必须按依赖顺序执行，不得并行。只改用户
目录，不写系统目录，也不使用 sudo。

## 使用方法

安装前只读检查：

```sh
sh scripts/check_host.sh
```

严格检查 Python 版本：

```sh
sh scripts/check_host.sh --require-python310
```

安装或修复当前用户环境：

```sh
sh scripts/install_goenv_manager.sh
```

只配置一种 shell 时，先单独导出变量，再执行脚本：

```sh
export GOENV_SHELL_ENV_TARGETS=zsh
sh scripts/install_shell_env.sh
```

```sh
export GOENV_SHELL_ENV_TARGETS=bash
sh scripts/install_shell_env.sh
```

保留或强制覆盖已有受管理文件：

```sh
export GOENV_PRESERVE=1
sh scripts/install_goenv_manager.sh
```

```sh
export GOENV_FORCE=1
sh scripts/install_goenv_manager.sh
```

安装 Python（可选镜像）：

```sh
pyenv-install 3.10
```

```sh
pyenv-install 3.11.9
```

默认直接从 python.org 下载。需要镜像时先设置 `PYENV_INSTALL_MIRRORS`
（空格分隔的镜像基础地址）：

```sh
export PYENV_INSTALL_MIRRORS="<mirror-base-url> ..."
```

可选 Go 模块设置（不设置则保持 Go 默认）：

```sh
export GOENV_GOPROXY=https://proxy.golang.org
export GOENV_GOPRIVATE=example.com
```

关闭单次编辑器配置：

```sh
goauto --no-vscode
```

```sh
export GOAUTO_VSCODE=0
goauto
```

只校验插件，或强制重装：

```sh
goauto --check-tools
```

```sh
goauto --install
```

`goauto --export` 只打印 export 语句，不修改当前环境。重新打开终端后，
`pyenv`、`goenv`、`pyenv-install` 和用户目录中的可执行文件应可直接调用。

## 错误处理

- Git 安装或版本复核失败时立即停止，不得继续安装 pyenv 或 goenv。
- pyenv clone、Python 下载或 Python 编译失败时停止，并保留错误输出。
- 插件缺失、模块不匹配或版本不匹配时，普通自动切换会尝试重新安装；
  `goauto --check-tools` 则返回非零状态。
- `GOENV_PYTHON_VERSION` 低于 `3.10` 时拒绝执行。
- 不使用 sudo 写入 `/usr/bin`、`/usr/local/bin` 或系统库目录。
- 已存在的用户 shell 配置和运行文件默认保留；受管理文件按版本升级并创建
  `.bak` 备份。`GOENV_FORCE` 为 `1` 时覆盖全部，`GOENV_PRESERVE` 为 `1`
  时保留全部。
- `.vscode/settings.json` 不是纯 JSON、顶层不是对象或不可写时只告警，
  `goauto` 仍然成功，不得覆盖用户文件。
- `goauto --check-tools` 只做校验，不写 `.vscode/settings.json`，也不改变
  本地 Go 版本。
- 编辑器配置写入失败或未重连时，提示用户重启远端 VS Code/Comate 会话。
- shell hook 只报告错误，不得返回非零状态覆盖用户上一条命令的退出码。

## 相关文件

- 旧 Linux、Git、Python 或 shell 约束：
  [references/compatibility.md](references/compatibility.md)。
- 安装顺序、检查项、可选模块设置、shell hook 和验证：
  [references/operations.md](references/operations.md)。
- 只读检查：`scripts/check_host.sh`。
- 安装：`scripts/install_goenv_manager.sh`。
- shell 启动文件：`scripts/install_shell_env.sh`。
- 运行模板位于 `templates/`。修改实现后必须同步模板并重新验证。
