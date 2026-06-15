#!/bin/bash

set -e

. assert.sh

assert "echo"                           # no output expected
assert "echo foo" "foo"                 # output expected
assert "cat" "bar" "bar"                # output expected if input's given
assert_raises "true" 0 ""               # status code expected
assert_raises "exit 127" 127 ""         # status code expected
assert "head -1 < $0" "#!/bin/bash"     # redirections
assert "seq 2" "1\n2"                   # multi-line output expected
assert_raises 'read a; exit $a' 42 "42" # variables still work
assert "echo 1;
echo 2      # ^" "1\n2"                 # semicolon required!
assert_end demo

_clean() {
    _assert_reset # reset state
    DEBUG= STOP= INVARIANT=1 DISCOVERONLY= CONTINUE= # reset flags
    eval $* # read new flags
}

# clean output
assert "_clean; assert true; assert_end" \
"all 1 tests passed."
# error reports on failure
assert "_clean; assert 'seq 1'; assert_end" \
'test #1 "seq 1" failed:\n\texpected nothing\n\tgot "1"\n1 of 1 tests failed.'
assert "_clean; assert true '1'; assert_end" \
'test #1 "true" failed:\n\texpected "1"\n\tgot nothing\n1 of 1 tests failed.'
assert "_clean; assert 'true' 'foo' 'bar'; assert_end" \
'test #1 "true <<< bar" failed:\n\texpected "foo"\n\tgot nothing\n1 of 1 tests failed.'
# debug output (-v)
assert "_clean DEBUG=1; assert true; assert_end" \
".\nall 1 tests passed."
assert "_clean DEBUG=1; assert_raises false; assert_end" \
'X\ntest #1 "false" failed:\n\tprogram terminated with code 1 instead of 0
1 of 1 tests failed.'
# collect tests only (-d)
assert "_clean DISCOVERONLY=1; assert true; assert false; assert_end" \
"collected 2 tests."
# stop immediately on failure (-x)
assert "_clean STOP=1; assert_raises false; assert_end" \
'test #1 "false" failed:\n\tprogram terminated with code 1 instead of 0'
# runtime statistics (omission of -i)
assert_raises "_clean INVARIANT=;
assert_end | egrep 'all 0 tests passed in ([0-9]|[0-9].[0-9]{3})s'"
# always exit successfully (--continue)
assert_raises "bash -c '. assert.sh; assert_raises false; assert_end' '' --continue" 0
# skip
assert "_clean; skip; assert_raises false; assert_raises true; assert_end" \
"all 1 tests passed."
# conditional skip
assert "_clean; skip_if true; assert_raises false; assert_end;" \
"all 0 tests passed."
assert "_clean; skip_if false; assert_raises true; assert_end;" \
"all 1 tests passed."
assert "_clean; skip_if bash -c 'exit 1'; assert_raises false; assert_end;" \
"all 0 tests passed."
# subshells and pipes can be used in skip as well (albeit escaped)
assert "_clean; skip_if 'cat /etc/passwd | grep \$(echo \$USER)';
assert_raises false; assert_end;" \
"all 0 tests passed."
assert_end output

# stderr should NOT leak if ignored
assert "_clean; assert less" ""
# stderr should be redirectable though
assert '_clean; assert "less 2>&1" "Missing filename (\"less --help\" for help)"'
# bash failures behave just like stderr
assert "_clean; assert ___invalid" ""
# test suites can be nested and settings are inherited
# (ie. we don't need to invoke the inner suite with the very same options,
# namely --invariant)
assert "_clean; bash -c '
. assert.sh;
assert_raises true; assert_end outer;
bash -c \". assert.sh; assert_raises true; assert_end inner\"
' '<exec>' --invariant" "all 1 outer tests passed.
all 1 inner tests passed."  # <exec> is $0
# set the correct exit status
assert_raises "_clean; bash -c \"
. assert.sh; assert true ''; assert_end one;
assert 'echo bar' 'bar'; assert_end two\"" 0
assert_raises "_clean; bash -c \"
. assert.sh; assert true 'foo'; assert_end one;
assert 'echo bar' 'bar'; assert_end two\"" 1
# ..but do not override it
assert_raises "_clean; bash -c \"
. assert.sh; assert true 'foo'; assert_end one;
assert 'echo bar' 'bar'; assert_end two; exit 3\"" 3
# environment variables do not leak
assert "_clean; x=0; assert 'x=1'; assert_raises 'x=2'; echo \$x" 0
assert "_clean; x=0; assert 'export x=1'; assert_raises 'export x=2';
echo \$x" 0
# options do not leak
assert_raises "set +e"
assert_raises "shopt -o errexit"
# skip properly resets all options
assert_raises "_clean; set +e; skip; assert_raises false; shopt -o errexit" 1
assert_raises "_clean; set -e; skip; assert_raises false; shopt -o errexit"
assert_raises "_clean; shopt -u extdebug; skip; assert_raises false; shopt extdebug" 1
assert_raises "_clean; shopt -s extdebug; skip; assert_raises false; shopt extdebug"

assert_end interaction

# commit: fixed output to report all errors, not just the first
assert "_clean;
assert_raises false; assert_raises false;
assert_end" 'test #1 "false" failed:
\tprogram terminated with code 1 instead of 0
test #2 "false" failed:
\tprogram terminated with code 1 instead of 0
2 of 2 tests failed.'
# commit: added default value for assert_raises
assert_raises "_clean; assert_raises true; assert_end" 0
# commit: fixed verbose failure reports in assert_raises
assert "_clean DEBUG=1; assert_raises false; assert_end" 'X
test #1 "false" failed:
\tprogram terminated with code 1 instead of 0
1 of 1 tests failed.'
# commit: redirected assert_raises output
assert "_clean; assert_raises 'echo 1'; assert_end" "all 1 tests passed."
# commit: fixed --discover to reset properly
assert "_clean DISCOVERONLY=1;
assert 1; assert 1; assert_end;
assert 1; assert_end;" "collected 2 tests.\ncollected 1 tests."
# commit: stopped errors from leaking into other test suites
assert "_clean;
assert_raises false; assert_raises false; assert_end;
assert_raises false; assert_end" 'test #1 "false" failed:
\tprogram terminated with code 1 instead of 0
test #2 "false" failed:
\tprogram terminated with code 1 instead of 0
2 of 2 tests failed.
test #1 "false" failed:
\tprogram terminated with code 1 instead of 0
1 of 1 tests failed.'
# issue 1: assert.sh: line 87: DISCOVERONLY: unbound variable
assert "_clean; set -u; assert_raises true; assert true; assert_end" \
"all 2 tests passed."
# issue 3: Not working on Mac OS X 10.7.5
assert "
_date=20;
date() {
echo \${_date}N;
};
_clean INVARIANT=;
assert date 20N;
_date=22;
assert_end" "all 1 tests passed in 2.000s."
# commit: supported formatting codes
assert "echo %s" "%s"
assert "echo -n %s | wc -c" "2"
# date with no nanosecond support
date() {         # date mock
    echo "123N"
}
assert '_clean DEBUG=1 INVARIANT=; tests_starttime="0N"; assert_end' \
       '\nall 0 tests passed in 123.000s.'
unset -f date  # bring back original date
assert_end regression

# ============================================================
# Tests for refactored internal helpers
# ============================================================

# -- _format_value: empty input becomes "nothing"
assert "_format_value ''" "nothing"
# -- _format_value: non-empty input gets quoted
assert "_format_value hello" '"hello"'
# -- _format_value: strings with spaces get quoted
assert "_format_value 'hello world'" '"hello world"'

# -- _flatten_multiline: single line is unchanged
assert "_flatten_multiline 'hello'" "hello"
# -- _flatten_multiline: newlines become literal \n
assert "_flatten_multiline 'line1
line2'" 'line1\\nline2'
# -- _flatten_multiline: three lines
assert "_flatten_multiline 'a
b
c'" 'a\\nb\\nc'

# -- _format_failure_report: without stdin (set tests_ran for predictability)
assert "tests_ran=42; _format_failure_report 'oops' 'echo test'" \
       "test #42 \"echo test\" failed:$(printf '\n\t')oops"
# -- _format_failure_report: with stdin
assert "tests_ran=7; _format_failure_report 'oops' 'cat' 'input'" \
       "test #7 \"cat <<< input\" failed:$(printf '\n\t')oops"

# -- _format_elapsed_time: basic 1-second duration (raw ns values)
assert "_format_elapsed_time 1000000000 2000000000" " in 1.000s"
# -- _format_elapsed_time: sub-second precision
assert "_format_elapsed_time 1000000000 1500000000" " in 0.500s"
# -- _format_elapsed_time: zero duration
assert "_format_elapsed_time 5000000000 5000000000" " in 0.000s"

# -- _run_capture_stdout: captures stdout correctly
assert "_run_capture_stdout 'echo hello'; echo \$_run_output" "hello"
# -- _run_capture_stdout: captures multiline stdout (quote to preserve newlines)
assert "_run_capture_stdout 'seq 3'; echo \"\$_run_output\"" "1\n2\n3"
# -- _run_capture_stdout: suppresses stderr
assert "_run_capture_stdout 'echo err >&2'; echo \$_run_output" ""
# -- _run_capture_stdout: passes stdin
assert "_run_capture_stdout 'cat' 'hello'; echo \$_run_output" "hello"

# -- _run_capture_exitcode: success returns 0
assert "_run_capture_exitcode 'true'; echo \$_run_status" "0"
# -- _run_capture_exitcode: failure returns correct code
assert "_run_capture_exitcode 'exit 42'; echo \$_run_status" "42"
# -- _run_capture_exitcode: suppresses stdout
assert "_run_capture_exitcode 'echo hello'; echo \$_run_status" "0"

# -- _record_failure: increments tests_failed counter
assert "_clean; _record_failure 'msg' 'cmd'; echo \$tests_failed" "1"
# -- _record_failure: appends to tests_errors array (quote to preserve newlines)
assert "_clean; _record_failure 'msg' 'cmd'; echo \"\${tests_errors[0]}\"" \
       "test #0 \"cmd\" failed:$(printf '\n\t')msg"
# -- _record_failure: multiple failures accumulate
assert "_clean; _record_failure 'a' 'c1'; _record_failure 'b' 'c2'; echo \$tests_failed" "2"

# -- _debug_tick: silent without DEBUG
assert "_clean; _debug_tick '.'" ""
# -- _debug_tick: emits character with DEBUG
assert "_clean DEBUG=1; _debug_tick '.'" "."

# -- _assert_reset: resets all counters cleanly
assert "_clean; tests_ran=5; tests_failed=3; _assert_reset; echo \$tests_ran \$tests_failed" "0 0"

# -- return values are always 0 (set -e safety)
assert "_clean DISCOVERONLY=1; assert true; echo ok" "ok"
assert "_clean DISCOVERONLY=1; assert_raises true; echo ok" "ok"

assert_end internals
