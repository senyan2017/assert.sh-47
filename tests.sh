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

# --- robustness: quoting, argument forwarding, set -u, interactive noise ---

# quoting: significant whitespace inside a command must survive.  The command
# is evaluated as one string; it must not be word-split and rejoined (which
# would silently collapse the three spaces in "a   b" down to one).
assert 'echo "a   b"' "a   b"
# quoting: a single-quoted glob/dollar is data, not to be expanded
assert "printf %s 'a*b'" 'a*b'
assert "printf %s '\$PATH'" '$PATH'
# quoting: spaces, runs of spaces, newlines and dollar signs in stdin are fed
# to the command verbatim (the here-string must stay quoted)
assert "cat" "a b c" "a b c"
assert "cat" "x   y" "x   y"
assert "cat" 'a\nb' "a
b"
assert "cat" '$x' '$x'
# a multi-line command (semicolon/newline separated) still works when quoted
assert 'echo a;
echo "b   c"' "a\nb   c"

# argument forwarding: options reach a *sourced* assert.sh, and operands after
# a "--" terminator are NOT mistaken for options (no flag/operand bleed-through,
# even when nested or sourced from another script)
assert "bash -c '. assert.sh; assert true; assert_end fwd' '<exec>' --invariant -- --discover" \
"all 1 fwd tests passed."
assert "bash -c '. assert.sh; assert true; assert true; assert_end fwd' '<exec>' --invariant --discover" \
"collected 2 fwd tests."
# sourcing must not clobber the caller's own positional parameters
assert "INVARIANT=1 bash -c 'set -- keep1 keep2; . assert.sh; assert_end p; echo \$1 \$2' '<exec>'" \
"all 0 p tests passed.
keep1 keep2"

# skip_if: complex conditions must not be mangled by eval.  Collapsing the
# significant double spaces (the pre-fix behaviour) would flip this comparison
# from false to true and wrongly skip the test below.
assert "_clean; skip_if '[ \"a   b\" = \"a b\" ]'; assert_raises true; assert_end" \
"all 1 tests passed."
assert "_clean; skip_if '[ \"a   b\" = \"a   b\" ]'; assert_raises true; assert_end" \
"all 0 tests passed."

# set -u: a failing assert must not trip over unbound positional parameters
# when the optional expected-output and/or stdin arguments are omitted, and a
# command that exits non-zero must still be reported rather than crash
assert_raises "_clean; set -u; assert 'echo x' 'y'; assert_end" 0
assert_raises "_clean; set -u; assert 'echo x'; assert_end" 0
assert_raises "_clean; set -u; assert_raises 'exit 3' 0; assert_end" 0

# interactive history expansion is silenced: sourcing assert.sh turns it off so
# a literal '!' in a command or expected output is treated verbatim instead of
# spraying "<word>: event not found" noise over otherwise passing tests
assert "echo 'a!b'" "a!b"
assert_raises "set -H 2>/dev/null; . ./assert.sh; set -o | grep -q '^histexpand.*on'" 1
assert_raises "bash -ic '. ./assert.sh; assert \"echo done\" done; assert_end' 2>&1 | grep -q 'event not found'" 1

assert_end robustness
