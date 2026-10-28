# 版本记录

当前版本：`0.0.2`

## 0.0.2

- `.go-version` 动态更新：`go.mod` 的 `go` 版本高于 `.go-version` 时以
  `go.mod` 为准，通过 `goenv local` 重写 `.go-version`，并同步安装对应 Go、
  按新 `major.minor` 校验/重装插件、刷新 `.vscode/settings.json`。
- shell hook 同时监视 `.go-version` 与 `go.mod` 内容，原地修改后下一次提示符
  即触发更新，不再只在切换目录时触发。

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
