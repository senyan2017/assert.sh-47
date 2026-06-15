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

# stderr can be asserted directly, no 2>&1 plumbing required
assert_stderr "echo 'boom' >&2" "boom"
# stderr is expected to be empty by default
assert_stderr "echo quiet"
# multi-line stderr is supported just like assert's stdout
assert_stderr "printf 'a\nb\n' >&2" "a\nb"
# assert_output checks stdout, stderr and exit code in one go
assert_output "echo done; echo warn >&2" "done" "warn"  # success with a warning
assert_output "echo usage >&2; exit 64" "" "usage" 64   # failure printing usage
assert_output "true"                                     # all defaults (empty/empty/0)
# stdin is still forwarded to the command under test
assert_stderr "cat >&2" "ping" "ping"
assert_output "cat" "pong" "" 0 "pong"

# assert_stderr: clean pass output
assert "_clean; assert_stderr 'echo e >&2' 'e'; assert_end" \
"all 1 tests passed."
# assert_stderr: stderr defaults to empty
assert "_clean; assert_stderr 'echo only-stdout'; assert_end" \
"all 1 tests passed."
# assert_stderr: failure report pinpoints the stderr mismatch
assert "_clean; assert_stderr 'echo wrong >&2' 'right'; assert_end" \
'test #1 "echo wrong >&2" failed:\n\tstderr: expected "right"\n\tgot "wrong"\n1 of 1 tests failed.'
# assert_stderr: stdout is ignored, only stderr matters
assert "_clean; assert_stderr 'echo out; echo err >&2' 'err'; assert_end" \
"all 1 tests passed."
# assert_output: combined pass output
assert "_clean; assert_output 'echo o; echo e >&2; exit 4' 'o' 'e' 4; assert_end" \
"all 1 tests passed."
# assert_output: an exit-code-only mismatch is isolated
assert "_clean; assert_output 'echo hi' 'hi' '' 5; assert_end" \
'test #1 "echo hi" failed:\n\texit code: expected 5\n\tgot 0\n1 of 1 tests failed.'
# assert_output: a stderr-only mismatch is isolated (stdout & code OK)
assert "_clean; assert_output 'echo ok; echo bad >&2' 'ok' 'good' 0; assert_end" \
'test #1 "echo ok; echo bad >&2" failed:\n\tstderr: expected "good"\n\tgot "bad"\n1 of 1 tests failed.'
# assert_output: every dimension can fail at once and each is reported
assert "_clean; assert_output 'echo a; echo b >&2; exit 9' 'x' 'y' 0; assert_end" \
'test #1 "echo a; echo b >&2; exit 9" failed:\n\tstdout: expected "x"\n\tgot "a"\n\tstderr: expected "y"\n\tgot "b"\n\texit code: expected 0\n\tgot 9\n1 of 1 tests failed.'
# verbose: progress dots for a mix of old and new assertions
assert "_clean DEBUG=1; assert true; assert_stderr 'echo e >&2' 'e'; assert_output 'echo o' 'o'; assert_end" \
"...\nall 3 tests passed."
# verbose: failing new assertions emit an X just like the old ones
assert "_clean DEBUG=1; assert_stderr 'echo x >&2' 'y'; assert_end" \
'X\ntest #1 "echo x >&2" failed:\n\tstderr: expected "y"\n\tgot "x"\n1 of 1 tests failed.'
# discover: new assertions are counted but not run, mixed with old
assert "_clean DISCOVERONLY=1; assert true; assert_stderr 'echo e >&2' 'e'; assert_output 'false'; assert_end" \
"collected 3 tests."
# stop: halt on the first failing new assertion before later ones run
assert "_clean STOP=1; assert_stderr 'echo a >&2' 'b'; assert_stderr 'echo c >&2' 'c'; assert_end" \
'test #1 "echo a >&2" failed:\n\tstderr: expected "b"\n\tgot "a"'
# old and new assertions interleave without disturbing the running tally
assert "_clean;
assert true; assert_stderr 'echo e >&2' 'e';
assert_raises false 1; assert_output 'echo o; echo w >&2; exit 3' 'o' 'w' 3;
assert_end" \
"all 4 tests passed."
# skip applies to new assertions too (skipped tests are not counted)
assert "_clean; skip; assert_stderr 'echo z >&2' 'no'; assert_end" \
"all 0 tests passed."
assert "_clean; skip; assert_output 'false' 'x'; assert_end" \
"all 0 tests passed."
# new assertions set the suite exit status just like the old ones
assert_raises "_clean; bash -c \"
. assert.sh; assert_output 'echo o; echo e >&2' 'o' 'e'; assert_end one;
assert_stderr 'echo e >&2' 'e'; assert_end two\"" 0
assert_raises "_clean; bash -c \"
. assert.sh; assert_output 'echo o; echo e >&2' 'bad' 'e'; assert_end one;
assert_stderr 'echo e >&2' 'e'; assert_end two\"" 1

assert_end stderr

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
