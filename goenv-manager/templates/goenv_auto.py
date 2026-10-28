#!/usr/bin/env python3
# goenv-manager:version=0.0.2
"""Install and automatically select Go versions with goenv."""

import argparse
import json
import os
import re
import subprocess
import sys
from pathlib import Path

HOME = Path.home()
GOENV_ROOT = Path(os.environ.get("GOENV_ROOT", HOME / ".goenv"))
GOENV_BIN = GOENV_ROOT / "bin" / "goenv"
TOOL_ROOT = Path(os.environ.get("GOENV_BOOTSTRAP_GOBIN") or (HOME / "bin"))
PYENV_ROOT = Path(os.environ.get("PYENV_ROOT", HOME / ".pyenv"))
GOENV_USER_PREFIX = Path(os.environ.get("GOENV_USER_PREFIX", HOME / ".local"))
PLUGIN_MAP_PATH = HOME / "scripts" / "go_plugin_map.json"
VSCODE_DIR = ".vscode"
VSCODE_SETTINGS = "settings.json"
VERSION_RE = re.compile(r"^(?:go|v)?(1\.\d+(?:\.\d+)?)$")
# Optional Go module settings. Each key is persisted to the go env file only
# when the matching GOENV_* environment variable is set; by default the skill
# leaves Go's own configuration untouched.
MODULE_SETTINGS = (
    ("GO111MODULE", "GOENV_GO111MODULE"),
    ("GOPROXY", "GOENV_GOPROXY"),
    ("GOPRIVATE", "GOENV_GOPRIVATE"),
    ("GONOPROXY", "GOENV_GONOPROXY"),
    ("GONOSUMDB", "GOENV_GONOSUMDB"),
)


def run(args, *, check=True, env=None, timeout=None, cwd=None):
    """Run a command without passing user-controlled values through a shell."""
    try:
        return subprocess.run(
            [str(arg) for arg in args],
            check=check,
            text=True,
            capture_output=True,
            env=env,
            timeout=timeout,
            cwd=cwd,
        )
    except subprocess.TimeoutExpired:
        log(f"Command timed out: {' '.join(map(str, args))}", "ERROR")
        return None
    except OSError as exc:
        log(f"Could not run {' '.join(map(str, args))}: {exc}", "ERROR")
        return None


def log(message, level="INFO"):
    silent = os.environ.get("GOAUTO_SHELL") == "1"
    verbose = os.environ.get("GOAUTO_VERBOSE") == "1"
    if level in {"ERROR", "WARN"} or not silent or verbose:
        print(f"[{level}] {message}", file=sys.stderr)


def normalize(version):
    """Return a valid Go version with either major.minor or patch precision."""
    match = VERSION_RE.fullmatch((version or "").strip())
    return match.group(1) if match else None


def major_minor(version):
    return ".".join(version.split(".")[:2])


def find_project_root(start=None):
    current = (start or Path.cwd()).resolve()
    for directory in (current, *current.parents):
        if (directory / ".go-version").is_file() or (directory / "go.mod").is_file():
            return directory
    return None


def version_key(version):
    """Sortable tuple; a missing patch counts as 0 (go.mod `go 1.25` is 1.25.0)."""
    parts = [int(part) for part in version.split(".")]
    return tuple(parts + [0] * (3 - len(parts)))


def read_go_version_file(root):
    version_file = root / ".go-version"
    if not version_file.is_file():
        return None
    try:
        lines = version_file.read_text(encoding="utf-8").splitlines()
    except OSError as exc:
        log(f"Could not read {version_file}: {exc}", "WARN")
        return None
    return normalize(lines[0]) if lines else None


def read_go_mod_version(root):
    go_mod = root / "go.mod"
    if not go_mod.is_file():
        return None
    try:
        lines = go_mod.read_text(encoding="utf-8").splitlines()
    except OSError as exc:
        log(f"Could not read {go_mod}: {exc}", "WARN")
        return None
    for line in lines:
        fields = line.split()
        if len(fields) >= 2 and fields[0] == "go":
            return normalize(fields[1])
    return None


def version_from_files(root):
    """Pick the Go version for a project.

    go.mod's `go` directive is the minimum toolchain the module needs, so a
    .go-version below it is stale. In that case go.mod wins and the caller
    rewrites .go-version (through `goenv local`) and everything derived from it.
    """
    pinned = read_go_version_file(root)
    required = read_go_mod_version(root)
    if pinned and required and version_key(pinned) < version_key(required):
        log(f".go-version ({pinned}) is older than go.mod ({required}); using {required}")
        return required
    return pinned or required


def latest_patch(major_minor):
    result = run([GOENV_BIN, "install", "-l"], check=False, timeout=60)
    if not result or result.returncode != 0:
        return None

    candidates = []
    for line in result.stdout.splitlines():
        value = line.strip()
        if not value.startswith(f"{major_minor}."):
            continue
        parts = value.split(".")
        if len(parts) != 3 or not all(part.isdigit() for part in parts):
            continue
        candidates.append((tuple(int(part) for part in parts), value))
    return max(candidates)[1] if candidates else None


def installed(version):
    return (GOENV_ROOT / "versions" / version).is_dir()


def goenv_exec_env(version=None):
    env = os.environ.copy()
    env["PATH"] = f"{GOENV_ROOT / 'shims'}:{GOENV_ROOT / 'bin'}:{env.get('PATH', '')}"
    if version:
        env["GOENV_VERSION"] = version
    return env


def go_env_file_values(path):
    """Return non-empty KEY=VALUE entries stored in the go env file."""
    found = {}
    if path is None or not path.is_file():
        return found
    try:
        lines = path.read_text(encoding="utf-8").splitlines()
    except OSError as exc:
        log(f"Could not read {path}: {exc}", "WARN")
        return found
    for line in lines:
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        if value:
            found[key] = value
    return found


def ensure_module_proxy(version):
    """Persist optional Go module settings set via GOENV_* variables.

    A setting is written only when its GOENV_* variable has a non-empty value.
    With no variables set, nothing is written and Go's defaults apply.
    """
    requested = {}
    for key, var in MODULE_SETTINGS:
        value = os.environ.get(var)
        if value:
            requested[key] = value
    if not requested:
        return True

    env = goenv_exec_env(version)
    for key in requested:
        env.pop(key, None)
    located = run(
        [GOENV_BIN, "exec", "go", "env", "GOENV"],
        check=False,
        env=env,
        timeout=60,
    )
    if not located or located.returncode != 0 or not located.stdout.strip():
        details = located.stderr.strip() if located and located.stderr else "go env GOENV failed"
        log(f"Could not locate the Go env file; settings not written: {details}", "WARN")
        return True
    current = go_env_file_values(Path(located.stdout.strip()))
    missing = []
    for key, value in requested.items():
        if current.get(key):
            continue
        missing.append(f"{key}={value}")
    if not missing:
        return True
    write = run(
        [GOENV_BIN, "exec", "go", "env", "-w", *missing],
        check=False,
        env=env,
        timeout=60,
    )
    if not write or write.returncode != 0:
        details = write.stderr.strip() if write and write.stderr else "go env -w failed"
        log(f"Could not persist Go module settings with go env -w: {details}", "WARN")
        return True
    log("Persisted optional Go module settings")
    return True


def load_plugins():
    if not PLUGIN_MAP_PATH.exists():
        return {}
    try:
        return json.loads(PLUGIN_MAP_PATH.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        log(f"Could not read plugin map: {exc}", "WARN")
        return {}


def plugin_metadata(binary, env):
    result = run(
        [GOENV_BIN, "exec", "go", "version", "-m", str(binary)],
        check=False,
        env=env,
        timeout=60,
    )
    if not result or result.returncode != 0:
        return None

    metadata = {}
    for line in result.stdout.splitlines():
        fields = line.split()
        if not fields:
            continue
        if fields[0] == "path" and len(fields) >= 2:
            metadata["path"] = fields[1]
        elif fields[0] == "mod" and len(fields) >= 3:
            metadata["module"] = fields[1]
            metadata["version"] = fields[2]
    return metadata


def plugin_matches(name, binary, config, env):
    if not binary.is_file():
        log(f"{name} is missing: {binary}", "WARN")
        return False

    expected_version = config.get("version")
    expected_module = config.get("module")
    url = config.get("url", "")
    if not expected_module:
        expected_module = url.rsplit("@", 1)[0] if "@" in url else None
    if not expected_version or not expected_module:
        log(f"Plugin {name} must define module, version and url", "ERROR")
        return False
    if "@" not in url or url.rsplit("@", 1)[1] != expected_version:
        log(f"Plugin {name} url/version mismatch", "ERROR")
        return False

    metadata = plugin_metadata(binary, env)
    if not metadata:
        log(f"Could not inspect installed plugin {name}: {binary}", "WARN")
        return False

    actual_module = metadata.get("module")
    actual_version = metadata.get("version")
    if actual_module != expected_module or actual_version != expected_version:
        log(
            f"{name} mismatch: expected {expected_module}@{expected_version}, "
            f"found {actual_module or 'unknown'}@{actual_version or 'unknown'}",
            "WARN",
        )
        return False
    return True


def install_tools(version, force=False, check_only=False):
    minor = major_minor(version)
    plugins = load_plugins().get(minor, {})
    if not plugins:
        log(f"No tool mapping configured for Go {minor}", "WARN")
        return True

    tool_dir = TOOL_ROOT / minor
    tool_dir.mkdir(parents=True, exist_ok=True)
    env = goenv_exec_env(version)
    env["GOBIN"] = str(tool_dir)

    failed = False
    for name, config in plugins.items():
        if not isinstance(config, dict):
            log(f"Invalid configuration for tool {name}", "WARN")
            failed = True
            continue
        url = config.get("url")
        if not url:
            log(f"Missing URL for tool {name}", "WARN")
            continue
        binary = tool_dir / name
        matches = plugin_matches(name, binary, config, env)
        if check_only:
            if not matches:
                failed = True
            continue
        if matches and not force:
            continue
        action = "Reinstalling" if binary.exists() else "Installing"
        log(f"{action} {name} for Go {version}")
        result = run(
            [GOENV_BIN, "exec", "go", "install", url],
            check=False,
            env=env,
            timeout=300,
        )
        if not result or result.returncode != 0:
            details = result.stderr.strip() if result else "timeout"
            log(f"Failed to install {name}: {details}", "ERROR")
            failed = True
            continue
        if not plugin_matches(name, binary, config, env):
            log(f"Installed plugin {name} failed version validation", "ERROR")
            failed = True
    return not failed


def tools_path(gopath, tool_dir):
    """Deterministic PATH for the editor's Go tools.

    The machine PATH is deliberately not copied: it contains temporary and
    machine specific entries that would be written into the project file.
    """
    entries = [
        str(tool_dir),
        str(GOENV_ROOT / "shims"),
        str(GOENV_ROOT / "bin"),
        str(PYENV_ROOT / "shims"),
        str(PYENV_ROOT / "bin"),
        str(GOENV_USER_PREFIX / "bin"),
        f"{gopath}/bin",
        "/opt/homebrew/bin",
        "/opt/homebrew/sbin",
        "/usr/local/bin",
        "/usr/bin",
        "/bin",
        "/usr/sbin",
        "/sbin",
    ]
    unique = []
    for entry in entries:
        if entry and entry not in unique:
            unique.append(entry)
    return ":".join(unique)


def vscode_settings(version):
    """Workspace settings that let VS Code and Comate find the pinned tools."""
    minor = major_minor(version)
    tool_dir = TOOL_ROOT / minor
    gopath = os.environ.get("GOPATH") or str(HOME / "go")

    alternate = {"go": str(GOENV_ROOT / "shims" / "go")}
    for name, config in sorted(load_plugins().get(minor, {}).items()):
        if not isinstance(config, dict):
            continue
        binary = tool_dir / name
        if binary.is_file():
            alternate[name] = str(binary)

    tools_env = {
        "GOBIN": str(tool_dir),
        "GOPATH": gopath,
        "GOROOT": str(GOENV_ROOT / "versions" / version),
        "GOENV_ROOT": str(GOENV_ROOT),
        "GOENV_BOOTSTRAP_GOBIN": str(TOOL_ROOT),
        "GOENV_VERSION": version,
        "PATH": tools_path(gopath, tool_dir),
    }

    return {
        "go.goroot": str(GOENV_ROOT / "versions" / version),
        "go.gopath": gopath,
        "go.alternateTools": alternate,
        "go.toolsEnvVars": tools_env,
    }


def ensure_vscode_settings(project_root, version):
    """Merge the managed keys into <project>/.vscode/settings.json."""
    if os.environ.get("GOAUTO_VSCODE", "1") == "0":
        return True

    target = project_root / VSCODE_DIR / VSCODE_SETTINGS
    settings = {}
    if target.is_file():
        try:
            settings = json.loads(target.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError) as exc:
            log(f"Keeping {target}: it is not plain JSON ({exc})", "WARN")
            return True
        if not isinstance(settings, dict):
            log(f"Keeping {target}: top level value is not an object", "WARN")
            return True

    merged = dict(settings)
    for key, value in vscode_settings(version).items():
        if isinstance(value, dict) and isinstance(merged.get(key), dict):
            inner = dict(merged[key])
            inner.update(value)
            merged[key] = inner
        else:
            merged[key] = value

    if merged == settings:
        return True

    try:
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(
            json.dumps(merged, indent=4, ensure_ascii=False) + "\n", encoding="utf-8"
        )
    except OSError as exc:
        log(f"Could not write {target}: {exc}", "WARN")
        return True
    log(f"Updated {target} for Go {version}")
    return True


def emit_exports(version):
    tool_dir = TOOL_ROOT / major_minor(version)
    print(f'export GOAUTO_VERSION="{version}"')
    print(f'export GOAUTO_VERSION_MINOR="{major_minor(version)}"')
    print(f'export GOBIN="{tool_dir}"')
    print(f'export PATH="{tool_dir}:$PATH"')


def main():
    parser = argparse.ArgumentParser(
        description="Install and select Go versions with goenv"
    )
    parser.add_argument("--version", help="Go version, for example 1.22.5")
    parser.add_argument("--install", action="store_true", help="Reinstall configured tools")
    parser.add_argument("--no-tools", action="store_true", help="Skip tool installation")
    parser.add_argument(
        "--no-vscode",
        action="store_true",
        help="Do not write .vscode/settings.json for the project",
    )
    parser.add_argument(
        "--check-tools",
        action="store_true",
        help="Validate configured tools without installing or changing them",
    )
    parser.add_argument("--export", action="store_true", help="Print shell exports")
    args = parser.parse_args()

    if not GOENV_BIN.is_file():
        log(f"goenv not found at {GOENV_BIN}", "ERROR")
        return 1

    project_root = find_project_root()
    if args.version:
        version = normalize(args.version)
        if not version:
            log(f"Invalid Go version: {args.version}", "ERROR")
            return 2
    else:
        version = version_from_files(project_root) if project_root else None
    if not version:
        log("No valid Go version found in .go-version or go.mod")
        return 0
    if len(version.split(".")) == 2:
        requested = version
        version = latest_patch(version)
        if not version:
            log(f"Could not find an available patch release for Go {requested}", "ERROR")
            return 1

    if not installed(version):
        if args.check_tools:
            log(f"Go {version} is not installed; cannot validate tools", "ERROR")
            return 1
        log(f"Installing Go {version}")
        result = run([GOENV_BIN, "install", version], check=False, timeout=900)
        if not result or result.returncode != 0:
            details = result.stderr if result else "timeout"
            print(details, file=sys.stderr)
            return result.returncode if result else 1

    if not args.check_tools:
        local_result = run(
            [GOENV_BIN, "local", version],
            check=False,
            cwd=project_root or Path.cwd(),
        )
        if not local_result or local_result.returncode != 0:
            log(f"Could not set local Go version to {version}", "ERROR")
            return local_result.returncode if local_result else 1

    if not args.check_tools:
        ensure_module_proxy(version)

    if not args.no_tools and not install_tools(
        version, force=args.install, check_only=args.check_tools
    ):
        return 1

    if project_root is not None and not args.no_vscode and not args.check_tools:
        ensure_vscode_settings(project_root, version)

    if args.export:
        emit_exports(version)
    else:
        log(f"Go {version} environment is ready")
    return 0


if __name__ == "__main__":
    sys.exit(main())
