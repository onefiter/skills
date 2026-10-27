# 兼容性说明

## 版本门槛

Git 必须严格大于 `2.23`：

- `2.23`：拒绝；
- `2.23.0`：拒绝；
- `2.23.1`：接受。

版本必须按数字分段比较，不能直接按字符串比较。

建议检查：

```sh
git --version
bash --version
uname -srm
```

普通审计可以额外检查 `python3 --version`，最低要求是 `3.10`。安装流程
中如果 `python3` 不存在或版本低于 `3.10`，不应安装系统 Python；必须先
完成 Git bootstrap，再安装 pyenv，之后通过 `pyenv-install <version>`
安装不低于 `3.10` 的 Python 版本。

如果 Git 不存在或不满足门槛，安装器必须先从源码安装指定版本到用户目录，
默认前缀为 `~/.local`，默认源码包来自 GitHub：

```sh
https://github.com/git/git/archive/refs/tags/v2.43.0.tar.gz
```

可用 `GOENV_GIT_BOOTSTRAP_URL` 覆盖为任意镜像地址。

## CentOS/RHEL 7

CentOS 7 常见的是 Bash 4，但为了兼容 macOS，公共 shell 代码按 Bash 3.2
和 zsh 5 处理。

不能要求系统安装 Homebrew。可以检测 `yum` 或 `dnf`，但没有明确授权时
不能自动安装系统包。常见依赖包括：

- `git`
- `tar`
- `curl` 或 `wget`
- 如果需要编译 Git、通过 pyenv 编译 Python，或编译 Go 工具，还需要 C 编译器、`make`、
  `autoconf` 和标准构建工具

内核版本本身不能决定 Go 是否兼容，还需要检查：

- `uname -m` 返回的 CPU 架构；
- libc/glibc 版本；
- 目标 Go 版本；
- 可用编译器和链接器；
- 内存和磁盘空间。

如果系统没有 Python 3，或版本低于 `3.10`，安装器可以继续安装 pyenv，
但不能静默回退到 Python 2，也不能改为 `yum install python` 或安装系统
Python。当前生成的 Go 自动切换脚本运行时需要 Python `>=3.10`；该 Python
应由 pyenv 提供。

安装 Python 时使用用户命令 `pyenv-install`，例如：

```sh
pyenv-install 3.10
```

该命令默认直接执行 `pyenv install`（从 python.org 下载源码）。当设置了
`PYENV_INSTALL_MIRRORS`（空格分隔的镜像基础地址）时，先下载
`Python-<version>.tar.xz` 或 `.tgz` 到 `$(pyenv root)/cache`，再执行
`pyenv install`。

Git、pyenv、goenv 以及 Go 工具默认必须放在用户目录，例如
`~/.local/bin`、`~/.pyenv/bin`、`~/.pyenv/shims`、`~/.goenv/bin`、
`~/.goenv/shims` 和 `~/bin`。不能依赖 `/usr/bin` 或 `/usr/local/bin`
的写权限，也不能因为无权限而自动使用 sudo。

Linux/CentOS 安装 pyenv 时，默认使用：

```sh
git clone https://github.com/pyenv/pyenv.git ~/.pyenv
```

安装 goenv 时默认使用：

```sh
git clone --depth=1 https://github.com/syndbg/goenv.git ~/.goenv
```

如需镜像，可用 `GOENV_PYENV_REPO` 和 `GOENV_GOENV_REPO` 覆盖仓库地址。

## shell 可移植性

避免使用：

- 在共享函数中使用 zsh 特殊变量名；
- Bash 关联数组；
- `mapfile`、`readarray`、`[[ -v ... ]]` 等 Bash 4-only 语法；
- 未加引号的 shell 路径；
- `git -c http.sslVerify=false`。

数组分割必须分别实现 bash 和 zsh 分支；自动切换在 zsh 中注册
`chpwd`，在 bash 中使用 `PROMPT_COMMAND`。

## SSH、编辑器与启动文件

SSH 会话和编辑器进程不保证读取交互式 rc：

- `bash -l -c`（VS Code Remote 解析远端环境时使用）只读 `~/.bash_profile`、
  `~/.bash_login`、`~/.profile` 中的第一个，不读 `~/.bashrc`；
- `zsh -l -c` 只读 `~/.zshenv`、`~/.zprofile`、`~/.zlogin`，不读 `~/.zshrc`；
- `ssh host command` 这类 non-interactive 会话可能什么都不读。

因此加载 `~/.goenvrc` 的 block 必须写入上述 login 与 non-interactive 文件，
不能只写 `~/.bashrc` 或 `~/.zshrc`。同时：

- `.profile` 可能被 `dash` 等 POSIX shell 读取，`~/.goenvrc` 含 bash/zsh
  专有语法，所以只在判断 `BASH_VERSION` 或 `ZSH_VERSION` 之后再 source；
- Bash 3.2（macOS、CentOS 7 的系统 bash）没有 `chpwd`，只能使用
  `PROMPT_COMMAND`，并且必须先比较项目根目录再决定是否执行检测；
- 任何 shell 都可能重复 source 启动文件，`~/.goenvrc` 的 PATH 追加必须
  先去重，重复加载不得产生重复条目；
- 非交互式 shell 只做环境导出，不执行 `pyenv init`，也不注册 hook，避免
  拖慢编辑器启动的每个子进程。

编辑器只在启动 remote server 时解析一次环境，改完启动文件必须重启远端
服务器（VS Code：`Remote-SSH: Kill VS Code Server on Host`）才会生效。
