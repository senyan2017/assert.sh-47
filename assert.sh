#!/bin/bash
# assert.sh 1.2 - bash unit testing framework
# Copyright (C) 2009-2015 Robert Lehmann
#
# http://github.com/lehmannro/assert.sh
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU Lesser General Public License as published
# by the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Lesser General Public License for more details.
#
# You should have received a copy of the GNU Lesser General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

# ============================================================
# Internal architecture
# ============================================================
#
# 1. CLI parsing     — translates flags into env vars
# 2. Suite state     — _assert_reset, _timestamp
# 3. Execution       — _run_capture_stdout, _run_capture_exitcode
# 4. Formatting      — _format_value, _flatten_multiline,
#                      _format_failure_report, _format_elapsed_time
# 5. Recording       — _debug_tick, _record_failure (single funnel)
# 6. Public API      — assert, assert_raises, assert_end,
#                      skip, skip_if
# 7. Exit handling   — _assert_cleanup trap
#
# Every function that may return non-zero from a conditional
# expression ([[ … ]] && … or [[ … ]] || …) appends `|| :` or
# uses `return 0` so the framework is safe under `set -e`.
#

# ============================================================
# 1. CLI argument parsing
# ============================================================

export DISCOVERONLY=${DISCOVERONLY:-}
export DEBUG=${DEBUG:-}
export STOP=${STOP:-}
export INVARIANT=${INVARIANT:-}
export CONTINUE=${CONTINUE:-}

_assert_parse_args() {
    # _assert_parse_args "$@"
    # Parse command-line options and set the corresponding
    # environment variables.  Exits on -h/--help.
    local args
    args="$(getopt -n "$0" -l \
        verbose,help,stop,discover,invariant,continue vhxdic $*)" \
    || exit -1
    local arg
    for arg in $args; do
        case "$arg" in
            -h)
                echo "$0 [-vxidc]" \
                    "[--verbose] [--stop] [--invariant] [--discover] [--continue]"
                echo "`sed 's/./ /g' <<< "$0"` [-h] [--help]"
                exit 0;;
            --help)
                cat <<EOF
Usage: $0 [options]
Language-agnostic unit tests for subprocesses.

Options:
  -v, --verbose    generate output for every individual test case
  -x, --stop       stop running tests after the first failure
  -i, --invariant  do not measure timings to remain invariant between runs
  -d, --discover   collect test suites only, do not run any tests
  -c, --continue   do not modify exit code depending on overall suite status
  -h               show brief usage information and exit
  --help           show this help message and exit
EOF
                exit 0;;
            -v|--verbose)   DEBUG=1;;
            -x|--stop)      STOP=1;;
            -i|--invariant) INVARIANT=1;;
            -d|--discover)  DISCOVERONLY=1;;
            -c|--continue)  CONTINUE=1;;
        esac
    done
}
_assert_parse_args "$@"

# ============================================================
# 2. Suite state management
# ============================================================

_indent=$'\n\t' # format fragment: newline + tab for error reports

_timestamp() {
    # Return current time as nanoseconds since epoch.
    date +%s%N
}

_assert_reset() {
    # _assert_reset
    # Initialize (or re-initialize) all per-suite counters and
    # the error accumulator.  Also snapshots the current time
    # as the suite start time.
    tests_ran=0
    tests_failed=0
    tests_errors=()
    tests_starttime="$(_timestamp)"
}

# ============================================================
# 3. Command execution
# ============================================================

_run_capture_stdout() {
    # _run_capture_stdout <command> [stdin]
    # Execute command via eval, feed optional stdin, suppress stderr.
    # Captured stdout (trailing newlines stripped) is stored in
    # the global variable _run_output.
    _run_output="$(eval 2>/dev/null "$1" <<< ${2:-})" || true
}

_run_capture_exitcode() {
    # _run_capture_exitcode <command> [stdin]
    # Execute command via eval in a subshell, discard all output.
    # Exit code is stored in the global variable _run_status.
    _run_status=0
    (eval "$1" <<< ${2:-}) > /dev/null 2>&1 || _run_status=$?
}

# ============================================================
# 4. Formatting helpers
# ============================================================

_format_value() {
    # _format_value <string>
    # Render a value for display in failure messages.
    # Empty strings become "nothing"; everything else is quoted.
    if [[ -z "$1" ]]; then
        echo "nothing"
    else
        echo "\"$1\""
    fi
}

_flatten_multiline() {
    # _flatten_multiline <string>
    # Replace embedded newlines with the literal two-character
    # sequence \n so the result fits on a single report line.
    sed -e :a -e '$!N;s/\n/\\n/;ta' <<< "$1"
}

_format_failure_report() {
    # _format_failure_report <message> <command> [stdin]
    # Build the full failure report string:
    #   test #N "<command>[ <<< <stdin>]" failed:
    #           <message>
    local message="$1" command="$2" stdin="${3:-}"
    local cmd_display="$command${stdin:+ <<< $stdin}"
    echo "test #$tests_ran \"$cmd_display\" failed:${_indent}$message"
}

_format_elapsed_time() {
    # _format_elapsed_time <start_ns> <end_ns>
    # Produce a human-readable " in S.SSSs" string from two
    # nanosecond timestamps.
    local start="$1" end="$2"
    local elapsed
    elapsed="$(printf "%010d" \
        "$(( ${end/%N/000000000} - ${start/%N/000000000} ))")"
    echo " in ${elapsed:0:${#elapsed}-9}.${elapsed:${#elapsed}-9:3}s"
}

# ============================================================
# 5. Result recording — the single funnel for all outcomes
# ============================================================

_debug_tick() {
    # _debug_tick <character>
    # Print a single progress character (., X, s) when verbose
    # mode is active.  Silent otherwise.  Always returns 0 so
    # callers are safe under set -e.
    [[ -n "$DEBUG" ]] && echo -n "$1" || :
}

_record_failure() {
    # _record_failure <message> <command> [stdin]
    # Central failure handler shared by assert() and
    # assert_raises().  Builds the report string via
    # _format_failure_report, then either exits immediately
    # (--stop) or appends to tests_errors[] for assert_end().
    local report
    report="$(_format_failure_report "$1" "$2" "${3:-}")"
    _debug_tick "X"
    if [[ -n "$STOP" ]]; then
        [[ -n "$DEBUG" ]] && echo || :
        echo "$report"
        exit 1
    fi
    tests_errors[$tests_failed]="$report"
    (( tests_failed++ )) || :
}

# ============================================================
# 6. Public assertion API
# ============================================================

assert() {
    # assert <command> <expected stdout> [stdin]
    (( tests_ran++ )) || :
    [[ -z "$DISCOVERONLY" ]] || return 0

    local expected result
    expected="$(echo -ne "${2:-}")"
    _run_capture_stdout "$1" "${3:-}"
    result="$_run_output"

    if [[ "$result" == "$expected" ]]; then
        _debug_tick "."
        return 0
    fi

    # Build failure message using shared formatting helpers.
    result="$(_flatten_multiline "$result")"
    local got_display exp_display
    got_display="$(_format_value "$result")"
    exp_display="$(_format_value "${2:-}")"
    _record_failure \
        "expected $exp_display${_indent}got $got_display" \
        "$1" "${3:-}"
}

assert_raises() {
    # assert_raises <command> <expected code> [stdin]
    (( tests_ran++ )) || :
    [[ -z "$DISCOVERONLY" ]] || return 0

    local expected
    _run_capture_exitcode "$1" "${3:-}"
    expected="${2:-0}"

    if [[ "$_run_status" -eq "$expected" ]]; then
        _debug_tick "."
        return 0
    fi
    _record_failure \
        "program terminated with code $_run_status instead of $expected" \
        "$1" "${3:-}"
}

assert_end() {
    # assert_end [suite ..]
    local tests_endtime
    tests_endtime="$(_timestamp)"

    local tests="$tests_ran ${*:+$* }tests"

    # --discover: just report collection counts
    if [[ -n "$DISCOVERONLY" ]]; then
        echo "collected $tests."
        _assert_reset
        return 0
    fi

    [[ -n "$DEBUG" ]] && echo || :

    local report_time=""
    if [[ -z "$INVARIANT" ]]; then
        report_time="$(_format_elapsed_time "$tests_starttime" "$tests_endtime")"
    fi

    if [[ "$tests_failed" -eq 0 ]]; then
        echo "all $tests passed$report_time."
    else
        for error in "${tests_errors[@]}"; do echo "$error"; done
        echo "$tests_failed of $tests failed$report_time."
    fi
    tests_failed_previous=$tests_failed
    [[ $tests_failed -gt 0 ]] && tests_suite_status=1 || :
    _assert_reset
}

# ============================================================
# Skip mechanism
# ============================================================

skip_if() {
    # skip_if <command ..>
    (eval $@) > /dev/null 2>&1 && status=0 || status=$?
    [[ "$status" -eq 0 ]] || return 0
    skip
}

skip() {
    # skip  (no arguments)
    shopt -q extdebug && tests_extdebug=0 || tests_extdebug=1
    shopt -q -o errexit && tests_errexit=0 || tests_errexit=1
    # enable extdebug so returning 1 in a DEBUG trap handler skips next command
    shopt -s extdebug
    # disable errexit (set -e) so we can safely return 1 without causing exit
    set +o errexit
    tests_trapped=0
    trap _skip DEBUG
}

_skip() {
    if [[ $tests_trapped -eq 0 ]]; then
        # DEBUG trap for command we want to skip.  Do not remove the handler
        # yet because *after* the command we need to reset extdebug/errexit (in
        # another DEBUG trap.)
        tests_trapped=1
        _debug_tick "s"
        return 1
    else
        trap - DEBUG
        [[ $tests_extdebug -eq 0 ]] || shopt -u extdebug
        [[ $tests_errexit -eq 1 ]] || set -o errexit
        return 0
    fi
}

# ============================================================
# 7. Initialization & exit trap
# ============================================================

_assert_reset
: ${tests_suite_status:=0}  # remember if any of the tests failed so far
_assert_cleanup() {
    local status=$?
    # modify exit code if it's not already non-zero
    [[ $status -eq 0 && -z $CONTINUE ]] && exit $tests_suite_status || :
}
trap _assert_cleanup EXIT
