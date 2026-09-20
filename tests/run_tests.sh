#!/bin/bash
#
# The whole suite. No hardware, no Dell server, no Docker, no network, no
# dependency past bash and the coreutils any runner already has.
#
#   ./tests/run_tests.sh              run everything
#   ./tests/run_tests.sh -f dash      run only the cases whose name matches
#   ./tests/run_tests.sh --list       list them without running

set -uo pipefail

TESTS_DIRECTORY="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" > /dev/null && pwd)"
REPOSITORY_ROOT="$(dirname -- "$TESTS_DIRECTORY")"
cd "$REPOSITORY_ROOT" || exit 1

FILTER=""
LIST_ONLY=false
while [ $# -gt 0 ]; do
  case "$1" in
    -f | --filter) FILTER="${2:-}"; shift 2 ;;
    --list)        LIST_ONLY=true; shift ;;
    -h | --help)   sed -n '2,10p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *)             echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

# shellcheck source=tests/lib/harness.sh
. "$TESTS_DIRECTORY/lib/harness.sh"

# Discovered from the text rather than from the shell, so the order reported is
# declaration order rather than whatever order the shell hands them back in.
CASES=()
for CASE_FILE in "$TESTS_DIRECTORY"/cases/*.sh; do
  [ -e "$CASE_FILE" ] || continue
  # shellcheck source=/dev/null
  . "$CASE_FILE"
  while read -r CASE_NAME; do
    CASES+=("$CASE_NAME")
  done < <(grep -oE '^function[[:space:]]+test_[A-Za-z0-9_]+' "$CASE_FILE" | awk '{print $2}')
done

# Every case file is sourced into this one shell, so two cases sharing a name
# would silently replace one another and the suite would report a pass for a
# body that never ran. Refusing to start is the only safe answer.
DUPLICATES="$(printf '%s\n' "${CASES[@]}" | sort | uniq -d)"
if [ -n "$DUPLICATES" ]; then
  echo "duplicate test case names:" >&2
  printf '%s\n' "$DUPLICATES" | sed 's/^/  /' >&2
  exit 2
fi

if [ "${#CASES[@]}" -eq 0 ]; then
  echo "no test cases found" >&2
  exit 2
fi

# "1 assertion", not "1 assertions". Cheap, and a report nobody trusts the
# wording of is a report nobody reads closely.
function pluralise() {
  if [ "$1" = 1 ]; then printf '%s %s' "$1" "$2"; else printf '%s %ss' "$1" "$2"; fi
}

PASSED=0
FAILED=0
SKIPPED=0
TOTAL_ASSERTIONS=0

for CASE_NAME in "${CASES[@]}"; do
  READABLE="${CASE_NAME#test_}"
  READABLE="${READABLE//_/ }"

  if [ -n "$FILTER" ] && [[ "$CASE_NAME" != *"$FILTER"* ]]; then
    SKIPPED=$((SKIPPED + 1))
    continue
  fi

  if [ "$LIST_ONLY" = true ]; then
    echo "  $READABLE"
    continue
  fi

  # Each case gets its own sandbox and its own shell, so one leaking a variable
  # or leaving a file behind cannot reach the next. The counts come back over
  # the file descriptor rather than through the environment, which a subshell
  # would not give back.
  RESULT="$(
    ASSERTIONS=0
    FAILURES=()
    make_sandbox
    "$CASE_NAME" > /dev/null
    destroy_sandbox
    printf '%s\n' "$ASSERTIONS"
    printf '%s\n' "${FAILURES[@]}"
  )"
  CASE_ASSERTIONS="$(printf '%s' "$RESULT" | head -n 1)"
  CASE_FAILURES="$(printf '%s' "$RESULT" | tail -n +2 | grep -v '^$')"
  TOTAL_ASSERTIONS=$((TOTAL_ASSERTIONS + CASE_ASSERTIONS))

  # A case that asserted nothing passed by doing nothing, which is worse than a
  # failure because it is silent. It is reported as a failure.
  if [ "$CASE_ASSERTIONS" -eq 0 ]; then
    FAILED=$((FAILED + 1))
    printf '  FAIL  %s\n' "$READABLE"
    printf '          no assertions were made\n'
  elif [ -n "$CASE_FAILURES" ]; then
    FAILED=$((FAILED + 1))
    printf '  FAIL  %s (%s)\n' "$READABLE" "$(pluralise "$CASE_ASSERTIONS" assertion)"
    printf '%s\n' "$CASE_FAILURES" | sed 's/^/          /'
  else
    PASSED=$((PASSED + 1))
    printf '  ok    %s (%s)\n' "$READABLE" "$(pluralise "$CASE_ASSERTIONS" assertion)"
  fi
done

[ "$LIST_ONLY" = true ] && exit 0

echo
if [ "$FAILED" -gt 0 ]; then
  printf '%s passed, %s FAILED (%s)\n' "$PASSED" "$FAILED" "$(pluralise "$TOTAL_ASSERTIONS" assertion)"
  exit 1
fi
printf '%s test %s passed (%s)' "$PASSED" "$(pluralise "$PASSED" case | sed 's/^[0-9]* //')" "$(pluralise "$TOTAL_ASSERTIONS" assertion)"
[ "$SKIPPED" -gt 0 ] && printf ', %s skipped by the filter' "$SKIPPED"
echo
