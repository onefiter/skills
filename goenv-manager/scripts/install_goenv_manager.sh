#!/bin/sh
set -eu

ROOT=${GOENV_ROOT:-"$HOME/.goenv"}
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
SKILL_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
USER_PREFIX=${GOENV_USER_PREFIX:-"$HOME/.local"}
USER_BIN="$USER_PREFIX/bin"
SHELL_ENV_SCRIPT="$SCRIPT_DIR/install_shell_env.sh"
MANAGED_VERSION=0.0.1
PATH="$USER_BIN:$PATH"
export PATH

version_gt_223() {
    version=$1
    old_ifs=$IFS
    IFS=.
    set -- $version
    IFS=$old_ifs
    major=${1:-0}
    minor=${2:-0}
    patch=${3:-0}
    [ "$major" -gt 2 ] ||
        { [ "$major" -eq 2 ] && [ "$minor" -gt 23 ]; } ||
        { [ "$major" -eq 2 ] && [ "$minor" -eq 23 ] && [ "$patch" -gt 0 ]; }
}

version_ge_310() {
    version=$1
    old_ifs=$IFS
    IFS=.
    set -- $version
    IFS=$old_ifs
    major=${1:-0}
    minor=${2:-0}
    [ "$major" -gt 3 ] ||
        { [ "$major" -eq 3 ] && [ "$minor" -ge 10 ]; }
}

download_file() {
    url=$1
    output=$2
    if command -v curl >/dev/null 2>&1; then
        curl -fL "$url" -o "$output"
    elif command -v wget >/dev/null 2>&1; then
        wget -O "$output" "$url"
    else
        echo "curl or wget is required to bootstrap Git." >&2
        exit 1
    fi
}

install_git() {
    git_version=${GOENV_GIT_BOOTSTRAP_VERSION:-2.43.0}
    prefix=${GOENV_GIT_PREFIX:-"$USER_PREFIX"}
    work_dir=${TMPDIR:-/tmp}/goenv-manager-git-$$
    archive=$work_dir/git-$git_version.tar.gz
    archive_url=${GOENV_GIT_BOOTSTRAP_URL:-"https://github.com/git/git/archive/refs/tags/v$git_version.tar.gz"}

    mkdir -p "$work_dir" "$prefix"
    echo "Installing Git $git_version from $archive_url"
    echo "Git will be installed under user prefix: $prefix"
    download_file "$archive_url" "$archive"
    tar -xzf "$archive" -C "$work_dir"
    src_dir=$(find "$work_dir" -maxdepth 1 -type d ! -path "$work_dir" | sed -n '1p')
    if [ -z "$src_dir" ]; then
        echo "Could not find extracted Git source directory." >&2
        exit 1
    fi

    (
        cd "$src_dir"
        make configure
        ./configure --prefix="$prefix"
        make -j"$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 2)"
        make install
    )
    PATH="$prefix/bin:$PATH"
    export PATH
    rm -rf "$work_dir"
}

ensure_git() {
    if command -v git >/dev/null 2>&1; then
        git_version=$(git --version | awk '{print $3}')
        if version_gt_223 "$git_version"; then
            return
        fi
        echo "Git $git_version is too old; bootstrapping a newer Git from source."
    else
        echo "Git is not installed; bootstrapping Git from source."
    fi
    install_git

    git_version=$(git --version | awk '{print $3}')
    if ! version_gt_223 "$git_version"; then
        echo "Installed Git is still too old: $git_version" >&2
        exit 1
    fi
}

ensure_runtime_prerequisites() {
    if ! command -v sh >/dev/null 2>&1; then
        echo "POSIX shell is required." >&2
        exit 1
    fi
    if [ ! -f "$SHELL_ENV_SCRIPT" ]; then
        echo "missing shell environment script: $SHELL_ENV_SCRIPT" >&2
        exit 1
    fi
}

managed_version_of() {
    sed -n 's/.*goenv-manager:version=\([0-9][0-9.]*\).*/\1/p' "$1" 2>/dev/null | sed -n '1p'
}

# Copy a bundled template, upgrading files that goenv-manager created earlier.
# User files without either the version marker or the legacy signature are
# preserved; GOENV_FORCE=1 replaces everything, GOENV_PRESERVE=1 replaces
# nothing.
install_template() {
    source=$1
    target=$2
    legacy_pattern=${3:-}

    if [ -e "$target" ] && [ "${GOENV_PRESERVE:-0}" = 1 ]; then
        echo "preserving existing $target (GOENV_PRESERVE=1)"
        return
    fi

    if [ ! -e "$target" ]; then
        cp "$SKILL_DIR/templates/$source" "$target"
        echo "installed $target"
        return
    fi

    if [ "${GOENV_FORCE:-0}" = 1 ]; then
        cp "$target" "$target.bak"
        cp "$SKILL_DIR/templates/$source" "$target"
        echo "replaced $target with the bundled template (backup: $target.bak)"
        return
    fi

    current=$(managed_version_of "$target")
    if [ -z "$current" ]; then
        if [ -n "$legacy_pattern" ] && grep -F "$legacy_pattern" "$target" >/dev/null 2>&1; then
            current=legacy
        else
            echo "preserving existing $target (not created by goenv-manager)"
            return
        fi
    fi

    if [ "$current" = "$MANAGED_VERSION" ]; then
        echo "already current: $target ($current)"
        return
    fi

    cp "$target" "$target.bak"
    cp "$SKILL_DIR/templates/$source" "$target"
    echo "upgraded $target: $current -> $MANAGED_VERSION (backup: $target.bak)"
}

ensure_runtime_prerequisites
echo "Phase 1/3: checking and installing Git"
ensure_git
echo "Git is ready: $(git --version)"

echo "Phase 2/3: installing pyenv"
PYENV_ROOT=${PYENV_ROOT:-"$HOME/.pyenv"}
if ! command -v pyenv >/dev/null 2>&1; then
    if [ -e "$PYENV_ROOT" ] && [ ! -x "$PYENV_ROOT/bin/pyenv" ]; then
        echo "PYENV_ROOT exists but does not contain an executable pyenv: $PYENV_ROOT" >&2
        exit 1
    fi
    if [ ! -e "$PYENV_ROOT" ]; then
        git clone "${GOENV_PYENV_REPO:-https://github.com/pyenv/pyenv.git}" "$PYENV_ROOT"
    fi
fi
PATH="$PYENV_ROOT/bin:$PATH"
export PATH

if ! command -v pyenv >/dev/null 2>&1; then
    echo "pyenv installation completed but pyenv is not executable from PATH." >&2
    exit 1
fi

mkdir -p "$USER_BIN"
install_template pyenv-install "$USER_BIN/pyenv-install" "PYENV_INSTALL_MIRRORS"
chmod +x "$USER_BIN/pyenv-install"

PATH="$PYENV_ROOT/shims:$PYENV_ROOT/bin:$PATH"
export PATH

ensure_pyenv_python() {
    current_version=
    if command -v python3 >/dev/null 2>&1; then
        current_version=$(python3 --version 2>&1 | awk '/^Python [0-9]+\./ {print $2; exit}')
    fi
    if [ -n "$current_version" ] && version_ge_310 "$current_version"; then
        echo "Python $current_version satisfies the >= 3.10 requirement."
        return
    fi

    target_version=${GOENV_PYTHON_VERSION:-3.10.13}
    echo "Python ${current_version:-missing} does not satisfy >= 3.10; installing Python $target_version with pyenv."
    if ! version_ge_310 "$target_version"; then
        echo "GOENV_PYTHON_VERSION must be Python 3.10 or newer: $target_version" >&2
        exit 1
    fi

    installed=0
    if "$PYENV_ROOT/bin/pyenv" versions --bare 2>/dev/null |
        awk -v target="$target_version" '$1 == target { found=1 } END { exit !found }'
    then
        installed=1
    fi
    if [ "$installed" -eq 0 ]; then
        "$USER_BIN/pyenv-install" "$target_version"
    fi
    "$PYENV_ROOT/bin/pyenv" global "$target_version"
    "$PYENV_ROOT/bin/pyenv" rehash

    if ! PYENV_VERSION="$target_version" "$PYENV_ROOT/bin/pyenv" exec python3 --version >/dev/null 2>&1; then
        echo "Python $target_version was not made available through pyenv." >&2
        exit 1
    fi
    echo "Python $target_version is ready through pyenv."
}

ensure_pyenv_python

if ! "$SCRIPT_DIR/check_host.sh" --allow-missing-python; then
    echo "Host compatibility check failed; refusing to install." >&2
    exit 1
fi

if [ -e "$ROOT" ] && [ ! -x "$ROOT/bin/goenv" ]; then
    echo "GOENV_ROOT exists but does not contain an executable goenv: $ROOT" >&2
    exit 1
fi

echo "Phase 3/3: installing and configuring goenv"
if [ ! -e "$ROOT" ]; then
    git clone --depth=1 "${GOENV_GOENV_REPO:-https://github.com/syndbg/goenv.git}" "$ROOT"
fi

mkdir -p "$HOME/bin" "$HOME/scripts" "$ROOT/shims" "$ROOT/versions"
"$ROOT/bin/goenv" rehash

install_template goenvrc "$HOME/.goenvrc" "_goauto_autorun"
install_template goenv_auto.py "$HOME/scripts/goenv_auto.py" "GOENV_BOOTSTRAP_GOBIN"
install_template go_plugin_map.json "$HOME/scripts/go_plugin_map.json" "golang.org/x/tools/gopls@"
chmod +x "$HOME/scripts/goenv_auto.py"

echo "Configuring shell startup files so interactive, login and SSH/editor sessions load the Go environment"
GOENV_SHELL_ENV_TARGETS=${GOENV_SHELL_ENV_TARGETS:-all}
export GOENV_SHELL_ENV_TARGETS
sh "$SHELL_ENV_SCRIPT"

# Optional Go module settings (GOENV_GOPROXY, GOENV_GOPRIVATE, GOENV_GONOPROXY,
# GOENV_GONOSUMDB, GOENV_GO111MODULE) are exported by ~/.goenvrc and persisted
# to the go env file by goauto. Nothing is applied unless those variables are
# set, so Go's own defaults are left untouched by default.

verify_runtime_files() {
    for target in "$HOME/.goenvrc" "$HOME/scripts/goenv_auto.py" \
        "$HOME/scripts/go_plugin_map.json" "$USER_BIN/pyenv-install"; do
        if [ ! -e "$target" ]; then
            echo "missing runtime file after install: $target" >&2
            exit 1
        fi
    done

    if ! "$ROOT/bin/goenv" --version >/dev/null 2>&1; then
        echo "goenv is not runnable: $ROOT/bin/goenv" >&2
        exit 1
    fi

    if command -v bash >/dev/null 2>&1 && ! bash -n "$HOME/.goenvrc"; then
        echo "goenvrc failed bash syntax check" >&2
        exit 1
    fi

    if command -v zsh >/dev/null 2>&1 && ! zsh -n "$HOME/.goenvrc"; then
        echo "goenvrc failed zsh syntax check" >&2
        exit 1
    fi

    if command -v python3 >/dev/null 2>&1; then
        if ! python3 -m py_compile "$HOME/scripts/goenv_auto.py"; then
            echo "goenv_auto.py failed Python syntax check" >&2
            exit 1
        fi
        rm -rf "$HOME/scripts/__pycache__"
    fi

    configured=0
    for rc_file in "$HOME/.zshrc" "$HOME/.zprofile" "$HOME/.zshenv" \
        "$HOME/.bashrc" "$HOME/.bash_profile" "$HOME/.bash_login" "$HOME/.profile"; do
        if [ -f "$rc_file" ] && grep -F ".goenvrc" "$rc_file" >/dev/null 2>&1; then
            echo "loads .goenvrc: $rc_file"
            configured=$((configured + 1))
        fi
    done
    if [ "$configured" -eq 0 ]; then
        echo "no shell startup file loads .goenvrc; run $SHELL_ENV_SCRIPT" >&2
        exit 1
    fi
}

verify_runtime_files
echo "goenv installed at $ROOT"
echo "runtime files verified: $HOME/.goenvrc, $HOME/scripts/goenv_auto.py, $HOME/scripts/go_plugin_map.json"
echo 'Shell startup files configured. Reload your shell or run: . "$HOME/.goenvrc"'
echo 'Editors over SSH: restart the VS Code/Comate remote server so it picks up the new environment.'
