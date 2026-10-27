# 版本记录

当前版本：`0.0.1`

## 0.0.1

首个公开发布版本。作为通用 skill，管理跨平台的 Go/Python 版本：

- 检查并安装 Git、pyenv、goenv 到用户目录，按项目自动切换 Go 版本。
- Go 模块设置（`GOPROXY`、`GOPRIVATE`、`GONOPROXY`、`GONOSUMDB`、
  `GO111MODULE`）仅在显式设置对应 `GOENV_*` 变量时生效，默认不改动 Go
  配置。
- Git 源码、pyenv、goenv 默认使用 GitHub 官方仓库，可用
  `GOENV_GIT_BOOTSTRAP_URL`、`GOENV_PYENV_REPO`、`GOENV_GOENV_REPO`
  覆盖为任意镜像。
- `pyenv-install` 默认直接调用 `pyenv install`，仅在设置
  `PYENV_INSTALL_MIRRORS` 时走镜像下载。
