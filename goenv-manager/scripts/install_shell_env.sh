#!/bin/sh
# goenv-manager:version=0.0.2
#
# Load ~/.goenvrc from the shell startup files that interactive, login and
# non-interactive bash/zsh sessions actually read.
#
# ~/.bashrc and ~/.zshrc are only read by interactive shells. Editors that
# connect over SSH (VS Code Remote, Comate, remote terminals) start their
# server and their tool processes from a login or non-interactive shell, so
# Go tools installed under ~/bin/<major.minor> stay invisible to them unless
# the environment is loaded from login/non-interactive startup files too.
#
# The update is idempotent and only appends a marked block to user files.
set -eu

begin="# >>> goenv-manager >>>"
end="# <<< goenv-manager <<<"

home=${HOME:-}
if [ -z "$home" ]; then
    echo "HOME is not set; refusing to configure shell startup files." >&2
    exit 1
fi

targets=${GOENV_SHELL_ENV_TARGETS:-all}
case "$targets" in
    all|bash|zsh) ;;
    *)
        echo "GOENV_SHELL_ENV_TARGETS must be all, bash or zsh: $targets" >&2
        exit 2
        ;;
esac

standard_loader='if [ -f "$HOME/.goenvrc" ]; then
    . "$HOME/.goenvrc"
fi'

posix_loader='if [ -n "${BASH_VERSION:-}${ZSH_VERSION:-}" ] && [ -f "$HOME/.goenvrc" ]; then
    . "$HOME/.goenvrc"
fi'

configure_file() {
    target=$1
    loader=$2

    case "$target" in
        "$home"/*) ;;
        *)
            echo "Refusing to configure a file outside HOME: $target" >&2
            exit 1
            ;;
    esac

    if [ -e "$target" ] && grep -F "$begin" "$target" >/dev/null 2>&1; then
        echo "goenv-manager: already configured: $target"
        return 0
    fi

    if [ -e "$target" ] && grep -F ".goenvrc" "$target" >/dev/null 2>&1; then
        echo "goenv-manager: already loads .goenvrc: $target"
        return 0
    fi

    if [ ! -e "$target" ]; then
        : > "$target"
    fi

    {
        printf '\n%s\n' "$begin"
        printf '%s\n' "$loader"
        printf '%s\n' "$end"
    } >> "$target"
    echo "goenv-manager: configured $target"
}

bash_login_target() {
    for candidate in "$home/.bash_profile" "$home/.bash_login" "$home/.profile"; do
        if [ -e "$candidate" ]; then
            printf '%s' "$candidate"
            return 0
        fi
    done
    printf '%s' "$home/.bash_profile"
}

if [ "$targets" = "all" ] || [ "$targets" = "zsh" ]; then
    configure_file "$home/.zshrc" "$standard_loader"
    configure_file "$home/.zprofile" "$standard_loader"
    configure_file "$home/.zshenv" "$standard_loader"
fi

if [ "$targets" = "all" ] || [ "$targets" = "bash" ]; then
    configure_file "$home/.bashrc" "$standard_loader"
    login_target="$(bash_login_target)"
    if [ "$login_target" = "$home/.profile" ]; then
        configure_file "$login_target" "$posix_loader"
    else
        configure_file "$login_target" "$standard_loader"
    fi
fi

echo "goenv-manager: shell startup files configured for: $targets"
