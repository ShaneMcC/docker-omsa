#!/bin/bash
#
# The sandbox the entrypoint is run inside, the mocks it talks to, and the
# assertions the cases use.
#
# run.sh writes to absolute paths -- /opt/dell/srvadmin/etc, /sbin/init, /tmp --
# and a test run must not touch any of them on the machine it runs on. Rather
# than asking the script to carry a root prefix it would only ever need for the
# tests, the harness copies it and rewrites those paths into a temporary
# directory. That is the one compromise in here, and it is worth naming: the
# suite tests the script's logic, not the filesystem layout of the image. What
# the image lays out is the Dockerfile's business and the build's to prove.

# Written by the mocks, read by the assertions.
export SANDBOX MOCK_EXISTING_USERS MOCK_CALLS MOCK_CHPASSWD_STDIN
# Set by a case before calling run_entrypoint, read by the mocks.
export MOCK_ADDUSER_EXIT MOCK_CHPASSWD_EXIT

ENTRYPOINT_SOURCE="${ENTRYPOINT_SOURCE:-docker/run.sh}"

# One per test case. Everything a case writes lands in here and nowhere else.
function make_sandbox() {
  SANDBOX="$(mktemp -d)"
  mkdir -p "$SANDBOX/opt/dell/srvadmin/etc/srvadmin-storage" \
           "$SANDBOX/sbin" "$SANDBOX/bin" "$SANDBOX/tmp" "$SANDBOX/var/tmp"

  MOCK_EXISTING_USERS="$SANDBOX/passwd"
  MOCK_CALLS="$SANDBOX/calls"
  MOCK_CHPASSWD_STDIN="$SANDBOX/chpasswd.stdin"
  : > "$MOCK_EXISTING_USERS"
  : > "$MOCK_CALLS"
  : > "$MOCK_CHPASSWD_STDIN"
  MOCK_ADDUSER_EXIT=0
  MOCK_CHPASSWD_EXIT=0

  # The file run.sh edits with sed. A real image has it from srvadmin-storage.
  printf 'NonDellCertifiedFlag=yes\n' \
    > "$SANDBOX/opt/dell/srvadmin/etc/srvadmin-storage/stsvc.ini"

  write_mocks
  install_entrypoint
}

function destroy_sandbox() {
  [ -n "${SANDBOX:-}" ] && [ -d "$SANDBOX" ] && rm -rf "$SANDBOX"
}

# getent and adduser honour "--" exactly as the real ones do, because that is
# the behaviour half these cases are about. Everything they are asked is
# recorded, so a case can assert on what was called rather than only on what
# was left behind.
function write_mocks() {
  cat > "$SANDBOX/bin/getent" <<'MOCK'
#!/bin/sh
printf 'getent %s\n' "$*" >> "$MOCK_CALLS"
[ "$1" = passwd ] || exit 2
shift
case "$1" in
  --) shift ;;
  -*) echo "getent: invalid option -- '${1#-}'" >&2; exit 64 ;;
esac
grep -qx -- "$1" "$MOCK_EXISTING_USERS" 2>/dev/null || exit 2
printf '%s:x:1000:1000::/home/%s:/bin/sh\n' "$1" "$1"
MOCK

  cat > "$SANDBOX/bin/adduser" <<'MOCK'
#!/bin/sh
printf 'adduser %s\n' "$*" >> "$MOCK_CALLS"
case "$1" in
  --) shift ;;
  -*) echo "adduser: invalid option -- '${1#-}'" >&2; exit 2 ;;
esac
[ "${MOCK_ADDUSER_EXIT:-0}" = 0 ] || { echo "adduser: refused" >&2; exit "$MOCK_ADDUSER_EXIT"; }
printf '%s\n' "$1" >> "$MOCK_EXISTING_USERS"
MOCK

  cat > "$SANDBOX/bin/chpasswd" <<'MOCK'
#!/bin/sh
printf 'chpasswd\n' >> "$MOCK_CALLS"
cat >> "$MOCK_CHPASSWD_STDIN"
[ "${MOCK_CHPASSWD_EXIT:-0}" = 0 ] || { echo "chpasswd: failed" >&2; exit "$MOCK_CHPASSWD_EXIT"; }
MOCK

  # Deterministic, so a case can assert on the first line of output.
  cat > "$SANDBOX/bin/date" <<'MOCK'
#!/bin/sh
echo "MOCKED-DATE"
MOCK

  # Stands in for systemd. Reaching it is the whole question in several cases,
  # so it says so and stops rather than execing anything.
  cat > "$SANDBOX/sbin/init" <<'MOCK'
#!/bin/sh
echo "INIT REACHED"
MOCK

  chmod +x "$SANDBOX"/bin/* "$SANDBOX/sbin/init"
}

# The copy under test, with its absolute paths pointed at the sandbox.
function install_entrypoint() {
  sed -e "s#/opt/dell#$SANDBOX/opt/dell#g" \
      -e "s#/sbin/init#$SANDBOX/sbin/init#g" \
      -e "s#rm -Rf /tmp/\* /var/tmp/\*#rm -Rf $SANDBOX/tmp/* $SANDBOX/var/tmp/*#" \
      "$ENTRYPOINT_SOURCE" > "$SANDBOX/run.sh"
  chmod +x "$SANDBOX/run.sh"
}

# Runs the entrypoint. Its exit status lands in ENTRYPOINT_STATUS and its
# combined output in ENTRYPOINT_OUTPUT, so a case can assert on either without
# the run itself deciding whether the case continues.
function run_entrypoint() {
  ENTRYPOINT_OUTPUT="$(PATH="$SANDBOX/bin:$PATH" sh "$SANDBOX/run.sh" 2>&1)"
  ENTRYPOINT_STATUS=$?
  export ENTRYPOINT_OUTPUT ENTRYPOINT_STATUS
}

function existing_user() { printf '%s\n' "$1" >> "$MOCK_EXISTING_USERS"; }

# Writes a credential file inside the sandbox and prints its path, so a case can
# say what is in it without caring where it lives. The content is written as
# given : a case that wants a trailing newline asks for one.
function secret_file() {
  local PATH_TO="$SANDBOX/secret-$1"
  printf '%s' "$2" > "$PATH_TO"
  chmod 600 "$PATH_TO"
  printf '%s' "$PATH_TO"
}
function role_map() { cat "$SANDBOX/opt/dell/srvadmin/etc/omarolemap" 2>/dev/null; }
function storage_ini() { cat "$SANDBOX/opt/dell/srvadmin/etc/srvadmin-storage/stsvc.ini"; }
function calls_matching() { grep -c -- "$1" "$MOCK_CALLS" 2>/dev/null || true; }

# ---------------------------------------------------------------- assertions
#
# They record and carry on rather than stopping the case, so one run reports
# every failure it found instead of only the first. Where the rest of a case
# cannot run after one, write "assert_... || return 1".

ASSERTIONS=0
FAILURES=()

function _fail() { FAILURES+=("$1"); return 1; }

function assert_equals() {
  ASSERTIONS=$((ASSERTIONS + 1))
  [ "$1" = "$2" ] && return 0
  _fail "${3:-value} : expected [$1], got [$2]"
}

function assert_contains() {
  ASSERTIONS=$((ASSERTIONS + 1))
  case "$2" in *"$1"*) return 0 ;; esac
  _fail "${3:-output} : expected to contain [$1], got [$2]"
}

function assert_not_contains() {
  ASSERTIONS=$((ASSERTIONS + 1))
  case "$2" in *"$1"*) _fail "${3:-output} : expected NOT to contain [$1]"; return 1 ;; esac
  return 0
}

function assert_file_absent() {
  ASSERTIONS=$((ASSERTIONS + 1))
  [ ! -e "$1" ] && return 0
  _fail "${2:-file} : expected [$1] not to exist"
}
