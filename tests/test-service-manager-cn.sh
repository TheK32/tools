#!/usr/bin/env bash

set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT_DIR/service-manager-cn.sh"
TEMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TEMP_DIR"' EXIT

mkdir -p "$TEMP_DIR/bin"

cat > "$TEMP_DIR/bin/systemctl" <<'MOCK'
#!/usr/bin/env bash
set -Eeuo pipefail

if [[ "${1:-}" == --user ]]; then
    shift
fi

case "${1:-}" in
    show-environment)
        [[ "${SYSTEMCTL_MANAGER_AVAILABLE:-1}" == 1 ]] || exit 1
        ;;
    list-units)
        printf 'nginx.service loaded active running NGINX Web Server\n'
        printf 'ssh.service loaded active running OpenSSH server daemon\n'
        ;;
    show)
        shift
        if [[ " $* " == *' --value '* ]]; then
            printf 'loaded\n'
            exit 0
        fi
        for argument in "$@"; do
            [[ "$argument" == *.service ]] || continue
            printf 'Id=%s\n' "$argument"
            printf 'ActiveState=active\n'
            printf 'UnitFileState=enabled\n'
            printf 'Description=Mock %s\n' "$argument"
            printf 'MainPID=123\n'
            printf 'ActiveEnterTimestamp=Mon 2026-01-01 00:00:00 UTC\n\n'
        done
        ;;
    *)
        printf 'unexpected systemctl invocation: %s\n' "$*" >&2
        exit 1
        ;;
esac
MOCK
chmod +x "$TEMP_DIR/bin/systemctl"

assert_contains() {
    local text="$1"
    local expected="$2"
    [[ "$text" == *"$expected"* ]] || {
        printf 'Expected output to contain: %s\nActual output:\n%s\n' "$expected" "$text" >&2
        exit 1
    }
}

version_output="$(bash "$SCRIPT" --version)"
assert_contains "$version_output" 'service-manager-cn 0.2.0'

list_output="$(PATH="$TEMP_DIR/bin:$PATH" bash "$SCRIPT" list)"
assert_contains "$list_output" 'nginx.service'
assert_contains "$list_output" 'ssh.service'
assert_contains "$list_output" 'Web 服务器和反向代理'

if failure_output="$(SYSTEMCTL_MANAGER_AVAILABLE=0 PATH="$TEMP_DIR/bin:$PATH" bash "$SCRIPT" user-list 2>&1)"; then
    printf 'Expected user-list to fail when the user manager is unavailable.\n' >&2
    exit 1
fi
assert_contains "$failure_output" '无法连接当前用户的 systemd 管理器'

printf 'All tests passed.\n'
