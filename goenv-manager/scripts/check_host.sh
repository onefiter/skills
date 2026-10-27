#!/bin/sh
set -u

fail=0
require_python=0
python_satisfied=0

case "${1:-}" in
    "")
        ;;
    --allow-missing-python)
        require_python=0
        ;;
    --require-system-python|--require-python310)
        require_python=1
        ;;
    -h|--help)
        echo "Usage: $0 [--allow-missing-python|--require-system-python|--require-python310]"
        echo "Read-only host report. Only Git and (optionally) Python affect the exit status."
        exit 0
        ;;
    *)
        echo "Usage: $0 [--allow-missing-python|--require-system-python|--require-python310]" >&2
        exit 2
        ;;
esac

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

printf '%s\n' "platform=$(uname -s 2>/dev/null || echo unknown)"
printf '%s\n' "kernel=$(uname -r 2>/dev/null || echo unknown)"
printf '%s\n' "arch=$(uname -m 2>/dev/null || echo unknown)"
printf '%s\n' "shell=${SHELL:-unknown}"

if command -v git >/dev/null 2>&1; then
    git_version=$(git --version | awk '{print $3}')
    printf '%s\n' "git=$git_version"
    if version_gt_223 "$git_version"; then
        printf '%s\n' "git_gate=ok"
    else
        printf '%s\n' "git_gate=fail: requires Git > 2.23"
        fail=1
    fi
else
    printf '%s\n' "git_gate=fail: git is not installed"
    fail=1
fi

if command -v python3 >/dev/null 2>&1; then
    python3_version=$(python3 --version 2>&1 | awk '/^Python [0-9]+\./ {print $2; exit}')
    if [ -z "$python3_version" ]; then
        printf '%s\n' "python3=unavailable"
        printf '%s\n' "python3_gate=fail: could not read the Python 3 version"
        python_satisfied=0
        [ "$require_python" -eq 1 ] && fail=1
    elif version_ge_310 "$python3_version"; then
        printf '%s\n' "python3=$python3_version"
        printf '%s\n' "python3_gate=ok"
        python_satisfied=1
    else
        printf '%s\n' "python3=$python3_version"
        printf '%s\n' "python3_gate=deferred_to_pyenv: requires Python >= 3.10"
        [ "$require_python" -eq 1 ] && fail=1
    fi
else
    printf '%s\n' "python3=missing"
    printf '%s\n' "python3_gate=deferred_to_pyenv: requires Python >= 3.10"
    [ "$require_python" -eq 1 ] && fail=1
fi

if command -v bash >/dev/null 2>&1; then
    printf '%s\n' "bash=$(bash --version 2>/dev/null | sed -n '1p')"
else
    printf '%s\n' "bash=missing"
fi

if command -v zsh >/dev/null 2>&1; then
    printf '%s\n' "zsh=$(zsh --version 2>&1)"
else
    printf '%s\n' "zsh=missing"
fi

if [ -f /etc/centos-release ]; then
    printf '%s\n' "distribution=$(cat /etc/centos-release)"
elif [ -f /etc/os-release ]; then
    distribution=$(sed -n 's/^PRETTY_NAME=//p' /etc/os-release | tr -d '"')
    printf '%s\n' "distribution=${distribution:-unknown}"
else
    printf '%s\n' "distribution=unknown"
fi

printf '%s\n' "--- build and download prerequisites ---"
compiler=$(command -v cc 2>/dev/null || command -v gcc 2>/dev/null || command -v clang 2>/dev/null || true)
make_tool=$(command -v make 2>/dev/null || true)
download_tool=$(command -v curl 2>/dev/null || command -v wget 2>/dev/null || true)
tar_tool=$(command -v tar 2>/dev/null || true)
printf '%s\n' "compiler=${compiler:-missing}"
printf '%s\n' "make=${make_tool:-missing}"
printf '%s\n' "download_tool=${download_tool:-missing}"
printf '%s\n' "tar=${tar_tool:-missing}"

printf '%s\n' "--- runtime resources ---"
if command -v getconf >/dev/null 2>&1 && getconf GNU_LIBC_VERSION >/dev/null 2>&1; then
    printf '%s\n' "libc=$(getconf GNU_LIBC_VERSION 2>/dev/null)"
elif [ "$(uname -s 2>/dev/null)" = "Linux" ]; then
    printf '%s\n' "libc=unknown: getconf GNU_LIBC_VERSION is unavailable"
else
    printf '%s\n' "libc=not_glibc"
fi

memory_kb=
if [ -r /proc/meminfo ]; then
    memory_kb=$(awk '/^MemTotal:/ {print $2; exit}' /proc/meminfo)
elif command -v sysctl >/dev/null 2>&1; then
    memory_bytes=$(sysctl -n hw.memsize 2>/dev/null || true)
    if [ -n "${memory_bytes:-}" ]; then
        memory_kb=$((memory_bytes / 1024))
    fi
fi
[ -n "$memory_kb" ] && printf '%s\n' "memory_kb=$memory_kb"

disk_kb=$(df -Pk "${HOME:-/}" 2>/dev/null | awk 'NR==2 {print $4; exit}')
[ -n "${disk_kb:-}" ] && printf '%s\n' "home_disk_free_kb=$disk_kb"

printf '%s\n' "--- existing user installs ---"
home_prefix=${HOME:-/}
goenv_root=${GOENV_ROOT:-$home_prefix/.goenv}
pyenv_root=${PYENV_ROOT:-$home_prefix/.pyenv}
if [ -x "$goenv_root/bin/goenv" ]; then
    goenv_version=$("$goenv_root/bin/goenv" --version 2>/dev/null | sed -n '1p')
    printf '%s\n' "goenv=${goenv_version:-unknown}"
else
    printf '%s\n' "goenv=missing"
fi
if [ -x "$pyenv_root/bin/pyenv" ]; then
    pyenv_version=$("$pyenv_root/bin/pyenv" --version 2>/dev/null | sed -n '1p')
    printf '%s\n' "pyenv=${pyenv_version:-unknown}"
else
    printf '%s\n' "pyenv=missing"
fi
if [ -f "$home_prefix/.goenvrc" ]; then
    printf '%s\n' "goenvrc=present"
    goenvrc_version=$(sed -n 's/.*goenv-manager:version=\([0-9][0-9.]*\).*/\1/p' "$home_prefix/.goenvrc" 2>/dev/null | sed -n '1p')
    printf '%s\n' "goenvrc_version=${goenvrc_version:-unknown}"
else
    printf '%s\n' "goenvrc=missing"
fi

hook_count=0
for rc_file in "$home_prefix/.zshrc" "$home_prefix/.zprofile" "$home_prefix/.zshenv" \
    "$home_prefix/.bashrc" "$home_prefix/.bash_profile" "$home_prefix/.bash_login" \
    "$home_prefix/.profile"; do
    if [ -f "$rc_file" ] && grep -F ".goenvrc" "$rc_file" >/dev/null 2>&1; then
        printf '%s\n' "shell_rc_hook=$rc_file"
        hook_count=$((hook_count + 1))
    fi
done
if [ "$hook_count" -eq 0 ]; then
    printf '%s\n' "editor_shell_env=missing: no startup file loads .goenvrc"
else
    printf '%s\n' "editor_shell_env=configured (${hook_count} startup files)"
fi

if [ "$python_satisfied" -eq 0 ] && { [ -z "$compiler" ] || [ -z "$make_tool" ]; }; then
    printf '%s\n' "note=pyenv must build Python, but compiler and make are required; install build tools first"
fi

exit "$fail"
