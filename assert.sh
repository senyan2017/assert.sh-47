#!/bin/bash
# assert.sh 1.1 - bash unit testing framework
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

export DISCOVERONLY=${DISCOVERONLY:-}
export DEBUG=${DEBUG:-}
export STOP=${STOP:-}
export INVARIANT=${INVARIANT:-}
export CONTINUE=${CONTINUE:-}

args="$(getopt -n "$0" -l \
    verbose,help,stop,discover,invariant,continue vhxdic $*)" \
|| exit -1
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
  -c, --continue   do not modify exit code to test suite status
  -h               show brief usage information and exit
  --help           show this help message and exit
EOF
            exit 0;;
        -v|--verbose)
            DEBUG=1;;
        -x|--stop)
            STOP=1;;
        -i|--invariant)
            INVARIANT=1;;
        -d|--discover)
            DISCOVERONLY=1;;
        -c|--continue)
            CONTINUE=1;;
    esac
done

# --- module constants ------------------------------------------------------
# Verbose-mode (-v) progress markers, one character per test case.  Naming
# them keeps the "what gets printed" decision out of the control flow below.
_assert_mark_pass="."   # the test case matched its expectation
_assert_mark_fail="X"   # the test case failed
_assert_mark_skip="s"   # the test case was skipped
# Indentation prefix (newline + tab) for the diagnostic line of a failure.
_assert_indent=$'\n\t'

# --- suite state (lifecycle) -----------------------------------------------
# Every per-suite counter lives here.  Nothing else creates or clears these;
# the recording helpers mutate them and _assert_reset wipes them between
# suites.  Concentrating the state in one place is what keeps nested suites,
# --continue and --discover from leaking results into one another.
#
#   tests_ran        number of test cases registered in the current suite
#   tests_failed     how many of those failed
#   tests_errors     rendered failure reports, in the order they happened
#   tests_starttime  suite start timestamp (nanoseconds since the epoch)

_assert_reset() {
    tests_ran=0
    tests_failed=0
    tests_errors=()
    tests_starttime="$(date +%s%N)" # nanoseconds_since_epoch
}

# --- command execution -----------------------------------------------------
# The only two places a tested command is evaluated.  Both run inside the
# caller's command-substitution subshell, so any environment or option the
# command changes is confined there and never leaks back into the suite.

_assert_eval_stdout() {
    # _assert_eval_stdout <command> [stdin]
    # Echo the command's stdout.  Its stderr is discarded unless the command
    # redirects it explicitly (e.g. "cmd 2>&1").
    eval 2>/dev/null $1 <<< ${2:-}
}

_assert_eval_status() {
    # _assert_eval_status <command> [stdin]
    # Run the command with its output discarded and propagate its exit status
    # as our own return value.  The command runs in a subshell so anything it
    # changes (variables, shell options) is confined there.  Crucially we do
    # *not* wrap this in a command substitution: callers capture the status
    # with `|| status=$?` so the errexit state the command observes is the
    # suite's own, not a command substitution's (which always disables it).
    (eval $1 <<< ${2:-}) > /dev/null 2>&1
}

# --- report rendering ------------------------------------------------------
# Pure helpers: they read their arguments and echo a string, never touching
# suite state.  Centralising the formatting here is what stops every
# assertion from hand-rolling its own "nothing"/quoting/timing strings.

_assert_quote() {
    # _assert_quote <value>
    # "nothing" when the value is empty, otherwise the value in double quotes.
    [[ -z "$1" ]] && echo -n "nothing" || echo -n "\"$1\""
}

_assert_oneline() {
    # _assert_oneline <value>
    # Collapse embedded newlines into literal "\n" so a multi-line capture
    # still prints on a single report line.
    sed -e :a -e '$!N;s/\n/\\n/;ta' <<< "$1"
}

_assert_suite_label() {
    # _assert_suite_label <count> [suite ..]
    # The "<count> [suite ]tests" fragment shared by every suite summary.
    local count="$1"; shift
    echo -n "$count ${*:+$* }tests"
}

_assert_duration() {
    # _assert_duration <start_ns> <end_ns>
    # The runtime suffix " in S.MMMs"; empty when --invariant is in effect.
    [[ -n "$INVARIANT" ]] && return
    # Subtract, tolerating platforms whose date(1) lacks %N support: the
    # trailing literal "N" is rewritten to nine zeroes so arithmetic works.
    local elapsed
    elapsed="$(printf "%010d" "$(( ${2/%N/000000000} - ${1/%N/000000000} ))")"
    # Split the nanosecond count into seconds and milliseconds for display.
    echo -n " in ${elapsed:0:${#elapsed}-9}.${elapsed:${#elapsed}-9:3}s"
}

_assert_format_report() {
    # _assert_format_report <command> <stdin> <diagnostic>
    # The canonical failure line for the current test number.
    echo -n "test #$tests_ran \"$1${2:+ <<< $2}\" failed:${_assert_indent}$3"
}

# --- result recording ------------------------------------------------------
# The bridge between execution and rendering.  These own every mutation of
# the suite counters and decide what (if anything) is printed for one case.

_assert_register_test() {
    # Count the upcoming test case.  Returns non-zero in --discover mode so
    # the caller collects the case without ever running it.
    (( tests_ran++ )) || :
    [[ -z "$DISCOVERONLY" ]]
}

_assert_record_pass() {
    # The current test case matched its expectation.
    [[ -z "$DEBUG" ]] || echo -n "$_assert_mark_pass"
}

_assert_record_failure() {
    # _assert_record_failure <command> <stdin> <diagnostic>
    # The current test case failed: emit the marker, render the report and
    # either stop right away (-x) or stash it for the suite summary.
    [[ -n "$DEBUG" ]] && echo -n "$_assert_mark_fail"
    local report
    report="$(_assert_format_report "$1" "$2" "$3")"
    if [[ -n "$STOP" ]]; then
        [[ -n "$DEBUG" ]] && echo
        echo "$report"
        exit 1
    fi
    tests_errors[$tests_failed]="$report"
    (( tests_failed++ )) || :
}

# --- public assertions -----------------------------------------------------

assert() {
    # assert <command> [expected stdout] [stdin]
    _assert_register_test || return
    local expected output
    expected="$(echo -ne "${2:-}")"
    output="$(_assert_eval_stdout "$1" "${3:-}")" || true
    if [[ "$output" == "$expected" ]]; then
        _assert_record_pass
        return
    fi
    _assert_record_failure "$1" "${3:-}" \
        "expected $(_assert_quote "${2:-}")${_assert_indent}got $(_assert_quote "$(_assert_oneline "$output")")"
}

assert_raises() {
    # assert_raises <command> [expected exit code] [stdin]
    _assert_register_test || return
    local expected="${2:-0}"
    local status=0
    _assert_eval_status "$1" "${3:-}" || status=$?
    if [[ "$status" -eq "$expected" ]]; then
        _assert_record_pass
        return
    fi
    _assert_record_failure "$1" "${3:-}" \
        "program terminated with code $status instead of $expected"
}

# --- skip support ----------------------------------------------------------
# skip / skip_if cause the *next* test case to be passed over entirely -- it
# is never executed and therefore never counted.  This relies on a DEBUG
# trap under `extdebug`; the shell options touched here are saved and later
# restored by _skip so the suite environment is left exactly as it was.

skip_if() {
    # skip_if <command ..>
    # Skip the next test case if <command> succeeds.
    local status
    (eval $@) > /dev/null 2>&1 && status=0 || status=$?
    [[ "$status" -eq 0 ]] || return
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
        # DEBUG trap for the command we want to skip.  Do not remove the
        # handler yet: *after* the command we still need to reset the
        # extdebug/errexit options (in another DEBUG trap.)
        tests_trapped=1
        [[ -z "$DEBUG" ]] || echo -n "$_assert_mark_skip"
        return 1
    else
        trap - DEBUG
        [[ $tests_extdebug -eq 0 ]] || shopt -u extdebug
        [[ $tests_errexit -eq 1 ]] || set -o errexit
        return 0
    fi
}

# --- suite finalization & exit code ----------------------------------------

assert_end() {
    # assert_end [suite ..]
    # Close the current suite: print its summary, fold its outcome into the
    # overall status, then reset state for the next suite.
    tests_endtime="$(date +%s%N)"
    local label report_time error
    label="$(_assert_suite_label "$tests_ran" "$@")"

    if [[ -n "$DISCOVERONLY" ]]; then
        echo "collected $label."
        _assert_reset
        return
    fi

    [[ -n "$DEBUG" ]] && echo
    report_time="$(_assert_duration "$tests_starttime" "$tests_endtime")"

    if [[ "$tests_failed" -eq 0 ]]; then
        echo "all $label passed$report_time."
    else
        for error in "${tests_errors[@]}"; do echo "$error"; done
        echo "$tests_failed of $label failed$report_time."
    fi

    tests_failed_previous=$tests_failed
    [[ $tests_failed -gt 0 ]] && tests_suite_status=1
    _assert_reset
}

# --- bootstrap -------------------------------------------------------------

_assert_reset
: ${tests_suite_status:=0}  # remember if any of the tests failed so far

_assert_cleanup() {
    local status=$?
    # modify exit code if it's not already non-zero
    [[ $status -eq 0 && -z $CONTINUE ]] && exit $tests_suite_status
}
trap _assert_cleanup EXIT
