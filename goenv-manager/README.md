# goenv-manager

使用 [goenv](https://github.com/go-nv/goenv) 和 [pyenv](https://github.com/pyenv/pyenv)
在用户目录管理 Go/Python 版本，并按项目自动切换 Go 版本。支持 macOS 和 Linux
（含 CentOS/RHEL 7 等较旧系统），不使用 sudo，不写系统目录。

当前版本见 [VERSION.md](VERSION.md)。

## 功能

- 检查 Git、Python、shell、系统和 CPU 架构；Git 缺失或不高于 `2.23` 时从源码安装到用户目录。
- 按 Git -> pyenv -> goenv 顺序安装，Python 最低版本为 `3.10`。
- 进入项目目录时，根据 `.go-version` 或 `go.mod` 自动切换 Go 版本。
- `go.mod` 的 `go` 版本高于 `.go-version` 时，以 `go.mod` 为准，重写 `.go-version`，
  并同步安装对应 Go、校验或重装插件、刷新 `.vscode/settings.json`。
  在 shell 中原地修改这两个文件后，下一次提示符即生效。
- 按 Go 的 `major.minor` 管理 `gopls`、`dlv`、`goimports`、`gofumpt`、`gotests`、
  `impl`、`goplay`、`staticcheck`，并校验二进制内嵌的模块版本。
- 把环境写入交互、login 和 non-interactive shell 启动文件，使 SSH 下的 VS Code、
  Comate 看到同一套环境。
- 在 Go 项目根目录维护 `.vscode/settings.json`，指向该项目固定版本的 Go 与插件。

## 快速开始

```sh
# 只读检查主机
sh scripts/check_host.sh

# 安装或修复当前用户环境
sh scripts/install_goenv_manager.sh
```

安装后重新打开终端，`goenv`、`pyenv`、`pyenv-install` 即可直接使用。

## 常用命令

```sh
goauto                 # 按当前项目选择 Go 版本并安装插件
goauto --check-tools   # 只校验插件，不改任何文件
goauto --install       # 强制重装插件
goauto --no-vscode     # 本次不写 .vscode/settings.json
goinstall 1.25.3       # 安装并切换到指定版本
gols                   # 列出已安装的 Go 版本
pyenv-install 3.11.9   # 安装 Python，可配置镜像
```

## 环境变量

| 变量 | 作用 |
| --- | --- |
| `GOENV_PRESERVE=1` | 保留所有已存在的受管理文件 |
| `GOENV_FORCE=1` | 覆盖所有受管理文件（会创建 `.bak`） |
| `GOENV_SHELL_ENV_TARGETS` | 只配置 `zsh` 或 `bash` |
| `GOENV_PYTHON_VERSION` | 指定 Python 版本，低于 `3.10` 会被拒绝 |
| `GOAUTO_VSCODE=0` | 不写 `.vscode/settings.json` |
| `PYENV_INSTALL_MIRRORS` | `pyenv-install` 使用的镜像地址，空格分隔 |
| `GOENV_GIT_BOOTSTRAP_URL`、`GOENV_PYENV_REPO`、`GOENV_GOENV_REPO` | 覆盖 Git 源码、pyenv、goenv 的来源 |
| `GOENV_GOPROXY`、`GOENV_GOPRIVATE`、`GOENV_GONOPROXY`、`GOENV_GONOSUMDB`、`GOENV_GO111MODULE` | 仅在设置时写入对应 Go 配置，默认不改动 |

## 目录结构

```text
goenv-manager/
├── SKILL.md            skill 说明与触发条件
├── VERSION.md          版本记录
├── scripts/            check_host.sh、install_goenv_manager.sh、install_shell_env.sh
├── templates/          goenvrc、goenv_auto.py、go_plugin_map.json、pyenv-install
└── references/         operations.md（操作细则）、compatibility.md（旧系统约束）
```

修改实现后，需同步 `templates/` 并重新验证。受管理文件带有
`goenv-manager:version=<版本>` 标记，安装器会在版本升级时覆盖旧文件并创建 `.bak`。
