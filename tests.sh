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

# assert_stderr checks stderr directly (stdout and exit code are ignored)
assert "_clean; assert_stderr 'echo oops >&2' 'oops'; assert_end" \
"all 1 tests passed."
# stdout produced alongside stderr is ignored by assert_stderr
assert "_clean; assert_stderr 'echo out; echo oops >&2' 'oops'; assert_end" \
"all 1 tests passed."
# empty stderr is the default expectation
assert "_clean; assert_stderr true; assert_end" "all 1 tests passed."
# a stderr mismatch is reported as such
assert "_clean; assert_stderr 'echo boom >&2' 'bang'; assert_end" \
'test #1 "echo boom >&2" failed:\n\tstderr mismatch: expected "bang"\n\tgot "boom"\n1 of 1 tests failed.'
# unexpected stderr output is reported against "nothing"
assert "_clean; assert_stderr 'echo x >&2'; assert_end" \
'test #1 "echo x >&2" failed:\n\tstderr mismatch: expected nothing\n\tgot "x"\n1 of 1 tests failed.'
# multi-line stderr is collapsed for the report just like stdout
assert "_clean; assert_stderr 'seq 2 >&2' 'zzz'; assert_end" \
'test #1 "seq 2 >&2" failed:\n\tstderr mismatch: expected "zzz"\n\tgot "1\\n2"\n1 of 1 tests failed.'

# assert_stdout_stderr checks stdout and stderr together
assert "_clean; assert_stdout_stderr 'echo out; echo err >&2' 'out' 'err'; assert_end" \
"all 1 tests passed."
# real scenario: a command that succeeds but warns on stderr
assert "_clean; assert_stdout_stderr 'echo done; echo warn >&2' 'done' 'warn'; assert_end" \
"all 1 tests passed."
# only the mismatching stream is reported
assert "_clean; assert_stdout_stderr 'echo no; echo err >&2' 'yes' 'err'; assert_end" \
'test #1 "echo no; echo err >&2" failed:\n\tstdout mismatch: expected "yes"\n\tgot "no"\n1 of 1 tests failed.'
# both streams can fail and both are reported
assert "_clean; assert_stdout_stderr 'echo a; echo b >&2' 'x' 'y'; assert_end" \
'test #1 "echo a; echo b >&2" failed:\n\tstdout mismatch: expected "x"\n\tgot "a"\n\tstderr mismatch: expected "y"\n\tgot "b"\n1 of 1 tests failed.'
# stdin is forwarded and shown in the report
assert "_clean; assert_stdout_stderr 'cat' 'bye' '' 'hi'; assert_end" \
'test #1 "cat <<< hi" failed:\n\tstdout mismatch: expected "bye"\n\tgot "hi"\n1 of 1 tests failed.'

# assert_raises_stderr checks the exit code and stderr together
assert "_clean; assert_raises_stderr 'echo e >&2; exit 3' 3 'e'; assert_end" \
"all 1 tests passed."
# real scenario: a command that fails and prints usage on stderr
assert "_clean; assert_raises_stderr 'echo usage >&2; exit 2' 2 'usage'; assert_end" \
"all 1 tests passed."
# a wrong exit code alone is reported
assert "_clean; assert_raises_stderr 'echo e >&2; exit 1' 2 'e'; assert_end" \
'test #1 "echo e >&2; exit 1" failed:\n\tprogram terminated with code 1 instead of 2\n1 of 1 tests failed.'
# wrong code and wrong stderr are reported together
assert "_clean; assert_raises_stderr 'echo b >&2; exit 1' 2 'y'; assert_end" \
'test #1 "echo b >&2; exit 1" failed:\n\tprogram terminated with code 1 instead of 2\n\tstderr mismatch: expected "y"\n\tgot "b"\n1 of 1 tests failed.'
assert_end stderr

# old and new assertions mix in a single passing suite
assert "_clean;
assert true; assert_stderr 'echo e >&2' 'e';
assert_stdout_stderr 'echo o; echo e >&2' 'o' 'e';
assert_raises_stderr 'echo e >&2; exit 2' 2 'e'; assert_raises false 1;
assert_end" "all 5 tests passed."
# old and new failures are collected together, in order
assert "_clean; assert_raises false; assert_stdout_stderr 'echo a' 'b'; assert_end" \
'test #1 "false" failed:\n\tprogram terminated with code 1 instead of 0\ntest #2 "echo a" failed:\n\tstdout mismatch: expected "b"\n\tgot "a"\n2 of 2 tests failed.'
# verbose (-v) prints progress markers for new assertions too
assert "_clean DEBUG=1;
assert true; assert_stderr 'echo e >&2' 'e'; assert_stdout_stderr 'echo a' 'b';
assert_end" \
'..X\ntest #3 "echo a" failed:\n\tstdout mismatch: expected "b"\n\tgot "a"\n1 of 3 tests failed.'
# discover (-d) counts new assertions without running them
assert "_clean DISCOVERONLY=1;
assert true; assert_stderr a b; assert_stdout_stderr c d e;
assert_raises_stderr f 1 g; assert_end" "collected 4 tests."
# stop (-x) halts on the first failing new assertion
assert "_clean STOP=1; assert_stdout_stderr 'echo a' 'b'; assert_stdout_stderr true;
assert_end" \
'test #1 "echo a" failed:\n\tstdout mismatch: expected "b"\n\tgot "a"'
assert_end extended_interaction
