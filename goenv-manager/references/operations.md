# 操作说明

## 文件布局

管理器使用以下文件：

```text
~/.goenv/
~/.goenvrc
~/scripts/goenv_auto.py
~/scripts/go_plugin_map.json
~/bin/<major.minor>/
<项目根>/.vscode/settings.json
```

`scripts/install_shell_env.sh` 负责把加载 `~/.goenvrc` 的受管理 block 写入
`~/.zshrc`、`~/.zprofile`、`~/.zshenv`、`~/.bashrc` 和 bash login 文件
（`~/.bash_profile`、`~/.bash_login`、`~/.profile` 中第一个存在的，都不存在
时创建 `~/.bash_profile`）。操作必须幂等，不能重复追加；`.profile` 可能被
POSIX shell 读取，只能在其内部判断 `BASH_VERSION`/`ZSH_VERSION` 后再 source
`~/.goenvrc`。默认覆盖 bash 和 zsh 两套文件，可用
`GOENV_SHELL_ENV_TARGETS=bash|zsh|all` 收窄。`~/.goenvrc` 内部会设置 pyenv、
goenv 和用户可执行文件目录的 PATH 顺序，并在追加前去重，因此可以安全地
被多个启动文件重复 source。

## 受管理文件升级

`~/.goenvrc`、`~/scripts/goenv_auto.py`、`~/scripts/go_plugin_map.json` 和
`~/bin` 中的 `pyenv-install` 由本 skill 管理，文件内带有
`goenv-manager:version=<version>` 标记。安装器发现标记版本低于当前模板时，
先把旧文件复制为 `.bak`，再写入新模板，使老主机也能拿到行为修复；没有
标记也没有旧版签名的用户文件保持不变。

- `GOENV_FORCE=1`：覆盖所有目标文件并创建 `.bak` 备份；
- `GOENV_PRESERVE=1`：不修改任何已存在的目标文件；
- 升级后必须重新验证 `bash -n`、`zsh -n` 和 `python3 -m py_compile`。

## 版本解析

按以下优先级解析版本：

1. 命令行参数 `--version`；
2. 从当前目录向上查找最近的 `.go-version`；
3. 如果没有 `.go-version`，从最近项目根目录的 `go.mod` 读取 `go` 指令。

版本解析只有一份实现：`goenv_auto.py`。shell hook 通过
`goauto --export` 取得 `GOAUTO_VERSION`、`GOAUTO_VERSION_MINOR`、`GOBIN`
和 `PATH`，不得在 shell 中重复解析 `.go-version` 或 `go.mod`。因此只有
`go.mod`、没有 `.go-version` 的项目同样会切换到 `~/bin/<major.minor>`。

支持以下稳定版本格式：

```text
1.22
1.22.5
go1.22.5
v1.22.5
```

显式传入非法版本时必须以非零状态退出。

只提供 `major.minor` 时，查询 goenv 可用版本并选择数字上最大的 patch
版本；显式提供 patch 版本时必须保持不变。

## 工具安装

使用：

```text
goenv exec go install <module>@<固定版本>
```

执行命令时必须使用目标 Go 版本。工具安装失败必须向调用方显示，并返回
失败状态。

插件映射文件 `~/scripts/go_plugin_map.json` 按 Go 的 `major.minor` 管理。
每个插件必须配置 `module`、`version` 和固定版本的 `url`：

推荐插件集合参考 VS Code Go 扩展的工具清单：
`gopls`、`dlv`、`goimports`、`gofumpt`、`gotests`、`impl`、`goplay`、
`staticcheck`。`vscgo` 是扩展内部能力，不作为独立 Go 二进制安装。

```json
{
  "1.22": {
    "gopls": {
      "module": "golang.org/x/tools/gopls",
      "version": "v0.18.0",
      "url": "golang.org/x/tools/gopls@v0.18.0"
    }
  }
}
```

进入项目或执行 `goauto --install` 时，管理器会将插件安装到
`${GOENV_BOOTSTRAP_GOBIN:-$HOME/bin}/<major.minor>/`，再使用目标 Go 执行
`go version -m <binary>`，校验二进制内嵌的模块名和版本。插件缺失或版本
不匹配时会重新安装。shell hook 与 `goenv_auto.py` 必须使用同一
`GOENV_BOOTSTRAP_GOBIN`，否则工具会被安装到 PATH 之外。

插件映射中 `module` 是 `go version -m` 报告的模块行，`url` 是 `go install`
使用的包路径。例如 `github.com/go-delve/delve/cmd/dlv@v1.24.0` 的模块是
`github.com/go-delve/delve`。

只校验不安装：

```sh
goauto --check-tools
```

存在插件映射但任一插件缺失或版本不匹配时，`goauto --check-tools` 返回非零。

当前默认映射覆盖 Go `1.19` 至最新稳定 Go `1.27`。Go 版本升级到新的
`major.minor` 后，应先为该版本补充插件映射，再执行自动安装。

## shell 状态

进入 Go 项目后设置：

```text
GOBIN=<GOENV_BOOTSTRAP_GOBIN>/<major.minor>
PATH=<GOENV_BOOTSTRAP_GOBIN>/<major.minor>:...
GOAUTO_VERSION=<完整版本>
GOAUTO_VERSION_MINOR=<major.minor>
```

离开所有 Go 项目后，恢复基础 `GOBIN`，并从 PATH 移除旧的版本工具目录。
不能删除无关 PATH 项，也不能破坏 pyenv shims。

zsh 通过 `chpwd` 触发自动切换，bash 通过 `PROMPT_COMMAND`。两种 hook 都
先解析当前目录所属的项目根目录，并与上次处理过的根目录比较：根目录没有
变化时立即返回，因此 bash 的每个提示符、以及项目内子目录之间的 `cd` 都
不会重新执行插件校验；只有首次进入一个项目根目录才检测并应用 Go 版本。
离开项目后必须恢复基础 `GOBIN` 并从 PATH 移除版本工具目录。

hook 只负责报告错误，不得返回非零状态，以免覆盖用户上一条命令的退出
状态。`GOENVRC_HOOK=0` 可以完全关闭自动切换。

`~/.goenvrc` 按“环境”和“交互式初始化”两部分执行：

- 环境部分（所有 shell）：导出 `GOPATH`（默认 `$HOME/go`）、`GOBIN`、
  `PYENV_ROOT`、`GOENV_ROOT`、`GOENV_USER_PREFIX`、`GOENV_BOOTSTRAP_GOBIN`。
  可选模块设置（`GOENV_GOPROXY` 等）只在对应变量已设置时才导出。
  去重后写入 PATH，并定义 `goauto`、`goinstall`、`gols` 等函数；
- 交互式部分（仅交互式 shell）：执行 `pyenv init -`、注册 `chpwd` 或
  `PROMPT_COMMAND`，并立即运行一次 `_goauto_autorun`。

非交互式 shell（SSH 编辑器、扩展宿主、`zsh -c`）只执行环境部分即可看到
`~/.goenv/shims/go` 和 `~/bin/<major.minor>`，因为 shims 目录本身已在
PATH 中，无需 `pyenv init`。

`goenv exec` 和 shims 默认会把 `GOPATH` 改写成 `$HOME/go/$GOENV_VERSION`。
管理器必须导出 `GOENV_DISABLE_GOPATH=1`，让 shell、`go env GOPATH`、
`goenv exec go install` 和 `.vscode/settings.json` 中的 `go.gopath` 使用
同一个 `$GOPATH`；否则编辑器与终端会指向不同的 module cache。
`GOROOT` 仍然由 goenv 按版本设置，不能禁用。

可选模块设置只在对应 `GOENV_*` 变量被显式设置时才生效：

- `GOENV_GO111MODULE` → `GO111MODULE`
- `GOENV_GOPROXY` → `GOPROXY`
- `GOENV_GOPRIVATE` → `GOPRIVATE`
- `GOENV_GONOPROXY` → `GONOPROXY`
- `GOENV_GONOSUMDB` → `GONOSUMDB`

任一来源变量都未设置时，skill 不写任何 Go 模块设置，Go 自身默认行为
保持不变。设置后，`~/.goenvrc` 在 shell 中导出对应变量，`goauto` 用
`go env -w` 把值持久化到 go env 文件；go env 文件里已有非空值时保持
不变。不要把这组值写入 `go.toolsEnvVars`，否则会盖过用户已经配好的
代理。

## 编辑器与 SSH

VS Code Remote、Comate 通过 SSH 连接时，远端服务器和扩展宿主由 login 或
non-interactive shell 启动，不读取 `~/.bashrc`、`~/.zshrc`。为此：

- `scripts/install_shell_env.sh` 必须把加载 `~/.goenvrc` 的 block 同时写入
  zsh 的 `~/.zshrc`、`~/.zprofile`、`~/.zshenv` 和 bash 的 `~/.bashrc`、
  bash login 文件；
- 进入 Go 项目时 `goenv_auto.py` 维护 `<项目根>/.vscode/settings.json`。

`.vscode/settings.json` 只写受管理键：

```json
{
    "go.goroot": "<GOENV_ROOT>/versions/<version>",
    "go.gopath": "<GOPATH>",
    "go.alternateTools": {
        "go": "<GOENV_ROOT>/shims/go",
        "gopls": "<GOENV_BOOTSTRAP_GOBIN>/<major.minor>/gopls"
    },
    "go.toolsEnvVars": {
        "GOBIN": "<GOENV_BOOTSTRAP_GOBIN>/<major.minor>",
        "GOROOT": "<GOENV_ROOT>/versions/<version>",
        "GOENV_VERSION": "<version>",
        "PATH": "<版本工具目录>:<GOENV_ROOT>/shims:<GOENV_ROOT>/bin:...:/usr/bin:/bin"
    }
}
```

`go.alternateTools` 只登记插件映射中存在且已安装的二进制；合并时保留用户
原有的其他键；目标文件不是纯 JSON（含注释）或顶层不是对象时只告警，不做
覆盖。`--no-vscode` 或 `GOAUTO_VSCODE=0` 关闭该行为。

`go.toolsEnvVars.PATH` 使用固定的目录列表（版本工具目录、goenv/pyenv 的
bin 和 shims、`$GOPATH/bin` 以及 `/usr/local/bin`、`/usr/bin`、`/bin` 等），
不能直接复制机器 PATH：其中常包含临时目录和机器相关路径，写进项目文件后
既无意义又会产生噪声 diff。`GOROOT` 与 `go.goroot` 保持同一版本目录。

编辑 remote server 只在启动时解析一次环境变量，修改启动文件后必须重启
远端服务器（VS Code：`Remote-SSH: Kill VS Code Server on Host`）才生效。

`goauto` 会把解析结果应用到当前 shell；`goauto --export` 只打印 export
语句，供脚本自行 `eval`。

## 默认不执行的操作

以下操作不属于普通 Go/Python 环境安装流程，不能由 agent 自行推断执行：

- 修复或创建 `/usr/lib`、`/usr/lib64`、`/lib`、`/lib64` 下的库符号链接；
- 安装低于 Python 3.10 的版本；
- 并行执行 Git、Python 或系统库安装；
- 修改系统级动态链接器配置；
- 修改 `/etc/profile`、`/etc/bashrc`、`/etc/zshrc` 等系统启动文件，或用
  sudo 写入系统目录来让编辑器看到 Go 环境。

只有用户明确给出目标版本、目标文件和变更范围时，才可以单独评估这些
操作的必要性和风险。


## 安装约束

按下面的顺序安装，后一步依赖前一步。任一步失败就停止，不得并行。

1. 检查 `~/.zshrc`、`~/.bashrc`、`~/.profile`、已有的 `pyenv`、`goenv` 和 PATH。
2. Git 不存在或版本不大于 `2.23` 时，从
   `https://github.com/git/git/archive/refs/tags/v2.43.0.tar.gz`（可用
   `GOENV_GIT_BOOTSTRAP_URL` 覆盖）下载 `v2.43.0` 源码，安装到
   `${GOENV_USER_PREFIX:-$HOME/.local}`。不得写入 `/usr/bin` 或
   `/usr/local/bin`，不得使用 sudo，不得关闭 SSL 校验。
3. 再次验证 Git。失败则停止，不得 clone pyenv 或 goenv。
4. 没有 `pyenv` 时从 `https://github.com/pyenv/pyenv.git` 安装（可用
   `GOENV_PYENV_REPO` 覆盖）。不安装系统 Python，也不要求系统 Python
   预先存在。
5. 把 `pyenv-install` 安装到 `${GOENV_USER_PREFIX:-$HOME/.local}/bin`。
   `pyenv-install 3.10` 解析为 definitions 中最新的 `3.10.x`，默认直接
   执行 `pyenv install`；设置 `PYENV_INSTALL_MIRRORS` 时先下载源码到
   pyenv cache 再安装。当前 Python 缺失或低于 `3.10` 时，默认安装
   `3.10.13`。`GOENV_PYTHON_VERSION` 必须大于等于 `3.10`。
6. 只有 `goenv` 可执行文件不存在时才安装 goenv，默认使用
   `https://github.com/syndbg/goenv.git`（可用 `GOENV_GOENV_REPO` 覆盖）。
7. `scripts/install_goenv_manager.sh` 复制模板。带 `goenv-manager:version=`
   标记或旧版签名的受管理文件升级并保留 `.bak`；用户自己的文件默认保留。
8. `scripts/install_shell_env.sh` 把加载 `~/.goenvrc` 的 block 写入
   `~/.zshrc`、`~/.zprofile`、`~/.zshenv`、`~/.bashrc` 和 bash login 文件。
   不能只写交互式 rc。`.profile` 必须先判断 `BASH_VERSION` 或 `ZSH_VERSION`
   再 source。`GOENV_SHELL_ENV_TARGETS` 取 `bash`、`zsh` 或 `all`。
9. PATH 必须包含 pyenv 与 goenv 的 `bin`、`shims`、用户前缀 `bin` 和工具目录。
   生成的可执行文件只能放在用户目录。
10. 共享 shell 函数不得使用 zsh 特殊变量名，例如 `status` 或 `path`。
11. `~/.goenvrc` 必须可重复 source。只有交互式 shell 才执行 `pyenv init`
    并注册 hook。
12. 从当前目录向上查找最近的 `.go-version` 或 `go.mod`。
13. shell hook 必须复用 `goauto --export`，不得在 shell 中重复解析版本。
14. 进入 Go 项目时维护 `.vscode/settings.json` 的 `go.goroot`、`go.gopath`、
    `go.alternateTools` 和 `go.toolsEnvVars`。不要在这里强制写入模块代理。
    非纯 JSON 只告警。`GOAUTO_VSCODE=0` 或 `--no-vscode` 可关闭。
15. 安装工具使用 `goenv exec go install`。代理只使用环境或 go env 文件里
    已有的值；可选模块设置由 `GOENV_*` 变量补齐。
16. bash 与 zsh 都存在时分别做语法和行为验证。
17. bash hook 挂在 `PROMPT_COMMAND`，zsh hook 挂在 `chpwd`。先比较项目根
    目录，根目录未变化时立即返回。

## 只读检查

安装前运行：

```sh
sh scripts/check_host.sh
```

系统没有 Python 3，或版本低于 `3.10` 时，只报告
`python3_gate=deferred_to_pyenv`，不阻止安装。需要严格审计时：

```sh
sh scripts/check_host.sh --require-python310
```

检查至少覆盖：Git 必须大于 `2.23`；存在 POSIX shell；Python 门槛；
操作系统、发行版、CPU 架构和当前 shell；编译器、`make`、`tar`、
`curl` 或 `wget`、libc、内存和用户目录空间；已有 `goenv`、`pyenv`、
`~/.goenvrc` 版本、加载它的启动文件，以及 `editor_shell_env`。
CentOS/RHEL 7 不能依赖 Bash 4 语法或 Homebrew。退出状态只由 Git 和
严格审计时的 Python 决定。

## 安装后验证

至少执行：

```sh
git --version
```

```sh
goenv --version
```

```sh
pyenv --version
```

```sh
zsh -n ~/.goenvrc
```

```sh
bash -n ~/.goenvrc
```

然后确认检查输出里的 `goenvrc_version`、`shell_rc_hook` 和
`editor_shell_env`：

```sh
sh scripts/install_shell_env.sh
```

```sh
sh scripts/check_host.sh --allow-missing-python
```

行为验证使用临时项目：嵌套目录进入时 `GOBIN` 和工具 PATH 正确，离开后
基础 `GOBIN` 恢复。至少覆盖只有 `go.mod`、没有 `.go-version` 的项目，
以及 bash 在同一目录连续出现提示符时不重复自动切换。进入项目根目录只
触发一次检测；项目内 `cd` 不产生新的 `goauto` 调用，也不重复打印
`[goauto]`。生成的 `.vscode/settings.json` 必须是合法 JSON，包含
`go.alternateTools` 的绝对路径，且重复执行不改变文件内容。
