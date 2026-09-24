#!/bin/bash
# Regression test for the OSC 7 path percent-encoders embedded in the shell
# integration scripts. Each shell's encoder must produce byte-wise UTF-8
# RFC-3986 output: only [/._~A-Za-z0-9-] pass through; everything else (space,
# multi-byte, control bytes, and notably '+' and '%', which are NOT unreserved)
# is percent-encoded. A shell that is not installed is skipped, not failed.
#
# Covers bash, zsh, fish, tcsh, and xonsh (the last by exec'ing its pure encoder
# members into a stub class from python3).
#
# Usage: tools/test_shell_integration_encoders.sh
set -u

DIR="$(cd "$(dirname "$0")/.." && pwd)/Resources/shell_integration"
LOADER="$(cd "$(dirname "$0")/.." && pwd)/OtherResources/vendor_conf.d/iterm2-shell-integration-loader.fish"
fail=0

have() { command -v "$1" >/dev/null 2>&1; }

# --- per-shell encoders: echo the encoding of $1 (no trailing newline) ---

enc_bash() {
  { sed -n '/^function iterm2_encode_path/,/^}/p' "$DIR/iterm2_shell_integration.bash"
    echo 'iterm2_encode_path "$1"; printf "%s" "$_iterm2_encoded_path"'; } | bash -s "$1"
}

enc_zsh() {
  { sed -n '/  iterm2_encode_path() {/,/^    }/p' "$DIR/iterm2_shell_integration.zsh"
    echo 'iterm2_encode_path "$1"; printf "%s" "$_iterm2_encoded_path"'; } | zsh -s "$1"
}

enc_fish() {
  fish -c 'printf "%s" (string escape --style=url -- "$argv[1]")' "$1"
}

enc_tcsh() {  # uses the script's stored awk program; tcsh interpreter not required
  local awkprog
  awkprog=$(sed -n "s/.*_iterm2_urlencode_awk = '\(.*\)'.*/\1/p" \
            "$DIR/iterm2_shell_integration.tcsh")
  printf "%s" "$1" | env LC_ALL=C awk "$awkprog"
}

enc_xonsh() {
  python3 - "$DIR/iterm2_shell_integration.xonsh" "$1" <<'PY'
import sys
src = open(sys.argv[1]).read().splitlines()
ps = next(l for l in src if l.strip().startswith("_PATH_SAFE"))
start = next(i for i, l in enumerate(src) if l.strip().startswith("def _encode_path"))
indent = len(src[start]) - len(src[start].lstrip())
body = [src[start]]
for l in src[start + 1:]:
    if l.strip() and (len(l) - len(l.lstrip())) <= indent:
        break
    body.append(l)
def dedent(line): return line[indent:] if line.strip() else ""
ns = {}
exec("class Stub:\n    " + dedent(ps) + "\n    " + "\n    ".join(dedent(l) for l in body), ns)
sys.stdout.write(ns["Stub"]()._encode_path(sys.argv[2]))
PY
}

# --- test table: name | input | expected ---
# newline uses an actual LF; keep these as literals.
NL=$'\n'
run_cases() {
  local shell="$1" encfn="$2"
  local -a names inputs expected
  names=(golden newline slash empty query literalpct tilde)
  inputs=("/tmp/osc7 test/ü#?&+%~-_." "a${NL}b" "/" "" "?#" "/tmp/%41" "~/foo")
  # literalpct: the '%' of an already-percent-looking path must itself encode to
  # %25 (so the receiver can't double-decode "%41" into "A"). tilde: '~' is
  # unreserved and passes through.
  expected=("/tmp/osc7%20test/%C3%BC%23%3F%26%2B%25~-_." "a%0Ab" "/" "" "%3F%23" "/tmp/%2541" "~/foo")
  local i
  for i in "${!names[@]}"; do
    local got
    got=$("$encfn" "${inputs[$i]}")
    if [ "$got" = "${expected[$i]}" ]; then
      echo "ok   $shell/${names[$i]}"
    else
      echo "FAIL $shell/${names[$i]}"
      echo "     input:    $(printf '%q' "${inputs[$i]}")"
      echo "     expected: ${expected[$i]}"
      echo "     got:      $got"
      fail=1
    fi
  done
}

# Drive the REAL tcsh interpreter through the alias/quoting/arg-alignment layer
# (not just the awk program) for a creatable tricky directory, asserting the whole
# emitted OSC 7 URL. This is what actually regressed once (the single-quoted alias
# body, unquoted backticks, argument alignment); the awk-only row below can't see
# it. Limited to a path that can be a real cwd, so it can't cover newline/empty/`/`
# inputs — those stay covered by the awk-program row (tcsh-awk).
run_tcsh_alias() {
  local base sub full user host awkprog expected got
  base=$(mktemp -d) || { echo "skip tcsh-alias (mktemp failed)"; return; }
  sub="sp ace ü"
  full="$base/$sub"
  mkdir -p "$full" || { echo "skip tcsh-alias (mkdir failed)"; rm -rf "$base"; return; }
  # Expected: build the full URL the same way the alias does, using this shell's
  # verified encoder for the path so we only assert tcsh's emission layer.
  user="$USER"
  host=$(hostname -f 2>/dev/null)
  awkprog=$(sed -n "s/.*_iterm2_urlencode_awk = '\(.*\)'.*/\1/p" "$DIR/iterm2_shell_integration.tcsh")
  expected="7;file://${user}@${host}$(printf "%s" "$full" | env LC_ALL=C awk "$awkprog")?machineID=1:abc"
  # Generate a minimal tcsh script: the stored awk program, a known machineID
  # query, the real first _iterm2_print_osc7 alias, cd into the tricky dir, emit.
  local tmp; tmp=$(mktemp)
  { sed -n "/_iterm2_urlencode_awk = /p" "$DIR/iterm2_shell_integration.tcsh"
    echo 'set _iterm2_machine_id_query = "?machineID=1:abc"'
    sed -n '/set _iterm2_user = /p' "$DIR/iterm2_shell_integration.tcsh"
    sed -n "/alias _iterm2_print_osc7/{p;q;}" "$DIR/iterm2_shell_integration.tcsh"
    printf 'cd "%s"\n' "$full"
    echo '_iterm2_print_osc7'; } > "$tmp"
  got=$(tcsh -f "$tmp")
  rm -f "$tmp"; rm -rf "$base"
  if [ "$got" = "$expected" ]; then
    echo "ok   tcsh-alias/full-url"
  else
    echo "FAIL tcsh-alias/full-url"
    echo "     expected: $expected"
    echo "     got:      $got"
    fail=1
  fi
}

# The whole machineID feature rests on one interop invariant: the value each shell
# computes must be byte-identical to what iTermMachineIdentity computes on the app
# side (which is separately pinned by iTermMachineIdentityTests.testShellComputed...).
# Extract each shell's machine-id block, run it, and compare to the openssl
# reference so a drift in the key, the awk extraction, or the openssl format on
# any side goes red instead of silently degrading every verdict to .unknown.
run_machineid() {
  if [ "$(uname)" != "Darwin" ]; then echo "skip machineid (non-Darwin)"; return; fi
  local bsid ref
  bsid=$(sysctl -n kern.bootsessionuuid 2>/dev/null)
  if [ -z "$bsid" ]; then echo "skip machineid (no bootsessionuuid)"; return; fi
  ref="1:$(printf '%s' "$bsid" | /usr/bin/openssl dgst -sha256 -hmac "iterm2-osc7-machine-id" | awk '{print $NF}')"
  local marker="# Machine identity for OSC 7 localhost detection, computed ONCE"

  check_mid() {  # shell, got
    if [ "$2" = "$ref" ]; then echo "ok   machineid/$1"
    else echo "FAIL machineid/$1"; echo "     expected: $ref"; echo "     got:      $2"; fail=1; fi
  }

  have bash && check_mid bash "$({ sed -n "/$marker/,/^fi\$/p" "$DIR/iterm2_shell_integration.bash"; echo 'printf "%s" "$_iterm2_machine_id"'; } | bash)"
  have zsh  && check_mid zsh  "$({ sed -n "/$marker/,/^    fi\$/p" "$DIR/iterm2_shell_integration.zsh"; echo 'printf "%s" "$_iterm2_machine_id"'; } | zsh)"
  have fish && check_mid fish "$({ sed -n "/$marker/,/^    end\$/p" "$DIR/iterm2_shell_integration.fish"; echo 'printf "%s" "$_iterm2_machine_id"'; } | fish)"
  if have tcsh; then
    local tmp; tmp=$(mktemp)
    { sed -n '/if ( ! ($?_iterm2_machine_id) ) then/,/^      endif$/p' "$DIR/iterm2_shell_integration.tcsh"
      echo 'printf "%s" "$_iterm2_machine_id"'; } > "$tmp"
    check_mid tcsh "$(tcsh -f "$tmp")"; rm -f "$tmp"
  fi
  # xonsh's block uses xonsh-only syntax ($(), @.imp) that can't be run in
  # isolation, and its python hmac is definitionally the reference (openssl == python
  # hmac, verified above). Verify statically that it HMACs with the same key + algo.
  if grep -q 'b"iterm2-osc7-machine-id"' "$DIR/iterm2_shell_integration.xonsh" \
     && grep -q 'hashlib.sha256' "$DIR/iterm2_shell_integration.xonsh"; then
    echo "ok   machineid/xonsh (static: key + sha256)"
  else
    echo "FAIL machineid/xonsh (key or algorithm drifted)"; fail=1
  fi
}

# A space in a user-supplied iterm2_hostname must be stripped so the emitted URL
# stays parseable by NSURL (an unparseable URL drops the whole host+cwd report).
# Drive the real tcsh alias with a spaced iterm2_hostname and assert no space
# survives in the URL. (bash/zsh/fish/xonsh strip the same way; their emit function
# can't be driven non-interactively, so this pins the trickiest shell.)
# Assert a raw OSC 7 emission parses (via NSURL-equivalent urlsplit) with the cwd as
# the path and a host containing no '/', i.e. a structural char in iterm2_hostname
# was sanitized away rather than restructuring the URL (host=prod, path=/web1/...).
assert_sanitized_authority() {  # label, raw_emit, expected_cwd
  local url
  url=$(printf '%s' "$2" | tr -d '\033\007' | sed -n 's/.*\(file:\/\/[^ ]*\).*/\1/p')
  if printf '%s' "$url" | python3 -c "
import sys, urllib.parse as u
p = u.urlsplit(sys.stdin.read().strip())
sys.exit(0 if (p.scheme=='file' and p.path==sys.argv[1] and '/' not in (p.hostname or '')) else 1)
" "$3" 2>/dev/null; then
    echo "ok   $1"
  else
    echo "FAIL $1 (url=$url)"; fail=1
  fi
}

# A structural char in a user-supplied iterm2_hostname must be sanitized so it can't
# restructure the URL (recording the wrong directory / poisoning localhost). Drive
# the real emit and assert host has no '/' and the path is still the cwd.
_iterm2_bad_hosts=("my host" "prod/web1" "a?b" "a#b" "a@b")

run_tcsh_hostname_sanitize() {
  local h tmp got
  for h in "${_iterm2_bad_hosts[@]}"; do
    tmp=$(mktemp)
    { sed -n "/_iterm2_urlencode_awk = /p" "$DIR/iterm2_shell_integration.tcsh"
      echo 'set _iterm2_machine_id_query = "?machineID=1:abc"'
      printf 'set iterm2_hostname = "%s"\n' "$h"
      sed -n '/set _iterm2_user = /p' "$DIR/iterm2_shell_integration.tcsh"
      sed -n '/if ( $?iterm2_hostname ) then/,/endif/p' "$DIR/iterm2_shell_integration.tcsh"
      sed -n '/alias _iterm2_print_osc7/p' "$DIR/iterm2_shell_integration.tcsh" | sed -n '2p'
      echo 'cd /tmp'
      echo '_iterm2_print_osc7'; } > "$tmp"
    got=$(tcsh -f "$tmp"); rm -f "$tmp"
    assert_sanitized_authority "tcsh-hostname-sanitize/[$h]" "$got" /tmp
  done
}

run_fish_hostname_sanitize() {
  local h got
  for h in "${_iterm2_bad_hosts[@]}"; do
    got=$({ echo 'function iterm2_print_user_vars; end'
            printf 'set -g iterm2_hostname %s\n' "$h"
            echo 'set -g _iterm2_machine_id "1:abc"'
            sed -n '/function iterm2_write_remotehost_currentdir_uservars/,/^    end$/p' \
                "$DIR/iterm2_shell_integration.fish"
            echo 'cd /tmp'
            echo 'iterm2_write_remotehost_currentdir_uservars'; } | fish 2>/dev/null)
    assert_sanitized_authority "fish-hostname-sanitize/[$h]" "$got" /tmp
  done
}

# fish and xonsh have a native OSC 7 emitter that iTerm2 must suppress. Drive a real
# pty and assert every OSC 7 emitted AFTER our ShellIntegrationVersion marker
# carries ?machineID= (the one before it is xonsh's harmless pre-source startup
# emission). A report without the token is a third-party report that re-establishes
# the prompt and overrides the machineID locality verdict.
run_single_emitter() {
  have script || { echo "skip single-emitter (no script)"; return; }
  local shell out after seen bad
  for shell in fish xonsh; do
    have $shell || { echo "skip single-emitter/$shell (not installed)"; continue; }
    if [ "$shell" = fish ]; then
      # `fish -i -c` runs the commands but never renders a prompt, so the emit
      # never fires and the test would be vacuous. Feed commands on stdin with -C
      # for the source step so a real prompt cycle runs on each cd.
      out=$(printf 'cd /tmp\ncd /usr\nexit\n' | TERM=xterm TERM_PROGRAM=iTerm.app \
            script -q /dev/null fish -i -C "source $DIR/iterm2_shell_integration.fish" 2>&1)
    else
      out=$(TERM=xterm TERM_PROGRAM=iTerm.app script -q /dev/null xonsh --no-rc -i -c "source -e $DIR/iterm2_shell_integration.xonsh
cd /tmp
cd /usr" 2>&1)
    fi
    # Liveness (guard against a vacuous driver) uses the FULL output, which always
    # has at least one emission: fish emits our report per prompt, xonsh emits its
    # native report once at startup before this script is sourced. The bad-count -
    # machineID-less reports that would re-establish the prompt - is scoped AFTER our
    # version marker, which excludes xonsh's documented pre-source startup emission.
    local osc; osc=$(printf '%s' "$out" | tr '\007' '\n')
    after=$(printf '%s' "$osc" | sed -n '/ShellIntegrationVersion/,$p')
    seen=$(printf '%s' "$osc" | grep -c '7;file://')
    bad=$(printf '%s' "$after" | grep '7;file://' | grep -vc 'machineID=')
    if [ "${seen:-0}" -eq 0 ]; then
      echo "FAIL single-emitter/$shell (no OSC 7 seen at all - driver broken)"; fail=1
    elif [ "${bad:-0}" -eq 0 ]; then
      echo "ok   single-emitter/$shell"
    else
      echo "FAIL single-emitter/$shell ($bad OSC 7 without machineID)"
      printf '%s\n' "$after" | grep '7;file://' | grep -v 'machineID=' | sed 's/^/     /'
      fail=1
    fi
  done
}

# Degraded machine-id path: when the OS cannot be determined (uname missing), the
# fish block must (a) print nothing to stderr - the old unquoted `test (uname)` threw
# a parse error on empty output, and a missing uname prints fish's own "Unknown
# command" that the inner 2>/dev/null does not catch - and (b) cache "0:" (identity
# unavailable -> hostname fallback), NOT "1:" (a positive "not this Mac" that pins a
# real Mac to .remote). Run the extracted block with a PATH that has no uname.
run_fish_machineid_degraded() {
  have fish || { echo "skip fish-machineid-degraded (fish not installed)"; return; }
  local marker="# Machine identity for OSC 7 localhost detection, computed ONCE"
  local fishabs; fishabs=$(command -v fish)
  local T; T=$(mktemp -d); local errf="$T/err" outf="$T/out"
  { sed -n "/$marker/,/^    end\$/p" "$DIR/iterm2_shell_integration.fish"
    echo 'printf "%s" "$_iterm2_machine_id"'; } \
    | env -i PATH=/nonexistent HOME="$T" "$fishabs" >"$outf" 2>"$errf"
  local out err; out=$(cat "$outf"); err=$(cat "$errf"); rm -rf "$T"
  if [ -n "$err" ]; then
    echo "FAIL fish-machineid-degraded (nonempty stderr on missing uname)"
    printf '%s\n' "$err" | sed 's/^/     /'; fail=1
  elif [ "$out" = "0:" ]; then
    echo "ok   fish-machineid-degraded"
  else
    echo "FAIL fish-machineid-degraded (expected 0: on unknown OS, got [$out])"; fail=1
  fi
}

# Empty authority: an absent USER or an unresolvable hostname must still yield a URL
# that NSURL parses with the cwd intact (file://@host/cwd or file://user@/cwd). This
# is a pin, not a bug report - both forms parse today; the test guards against a
# future change that lets an empty component swallow the path.
run_fish_empty_authority() {
  have fish || { echo "skip fish-empty-authority (fish not installed)"; return; }
  local emit; emit=$(sed -n '/function iterm2_write_remotehost_currentdir_uservars/,/^    end$/p' "$DIR/iterm2_shell_integration.fish")
  local got
  # No user: file://@host/cwd
  got=$({ echo 'function iterm2_print_user_vars; end'
          echo 'set -e USER'
          echo 'set -g iterm2_hostname host.example'
          echo 'set -g _iterm2_machine_id "1:abc"'
          printf '%s\n' "$emit"
          echo 'cd /tmp'
          echo 'iterm2_write_remotehost_currentdir_uservars'; } | fish 2>/dev/null)
  assert_sanitized_authority "fish-empty-authority/[no-user]" "$got" /tmp
  # No host: hostname fails, iterm2_hostname unset -> file://user@/cwd
  got=$({ echo 'function iterm2_print_user_vars; end'
          echo 'function hostname; return 1; end'
          echo 'set -gx USER alice'
          echo 'set -g _iterm2_machine_id "1:abc"'
          printf '%s\n' "$emit"
          echo 'cd /tmp'
          echo 'iterm2_write_remotehost_currentdir_uservars'; } | fish 2>/dev/null)
  assert_sanitized_authority "fish-empty-authority/[no-host]" "$got" /tmp
}

# Suppression under the REAL injected-loader order: the vendored loader sources the
# integration on the first fish_prompt (after fish's native emitter exists), and our
# inline shadow must neutralize it immediately. Drive a real pty via the loader (not
# -C, which is the manual/pre-prompt order that run_single_emitter covers) and assert
# at most one bare OSC 7 (fish's startup run-once) plus our per-prompt machineID
# reports. A regression that lets native survive shows up as one extra bare report per
# cd. On fish 3.x this is exactly the case that broke before the one-shot+inline fix.
run_fish_loader_order() {
  have fish || { echo "skip fish-loader-order (fish not installed)"; return; }
  have script || { echo "skip fish-loader-order (no script)"; return; }
  [ -f "$LOADER" ] || { echo "skip fish-loader-order (loader not found)"; return; }
  local T; T=$(mktemp -d)
  mkdir -p "$T/home/.config/fish" "$T/home/.local/share" "$T/vendored/fish/vendor_conf.d"
  cp "$LOADER" "$T/vendored/fish/vendor_conf.d/iterm2-shell-integration-loader.fish"
  cp "$DIR/iterm2_shell_integration.fish" "$T/vendored/iterm2_shell_integration.fish"
  local out
  out=$(printf 'cd /tmp\ncd /usr\nexit\n' \
        | env HOME="$T/home" XDG_CONFIG_HOME="$T/home/.config" XDG_DATA_HOME="$T/home/.local/share" \
              XDG_DATA_DIRS="$T/vendored" IT2_FISH_XDG_DATA_DIRS="$T/vendored" \
              TERM=xterm TERM_PROGRAM=iTerm.app LC_TERMINAL=iTerm2 \
              script -q /dev/null fish -i 2>&1)
  rm -rf "$T"
  local osc total bare mid
  osc=$(printf '%s' "$out" | tr '\007' '\n')
  total=$(printf '%s' "$osc" | grep -c '7;file://')
  bare=$(printf '%s' "$osc" | grep '7;file://' | grep -vc 'machineID=')
  mid=$(printf '%s' "$osc" | grep '7;file://' | grep -c 'machineID=')
  if [ "${total:-0}" -eq 0 ]; then
    echo "FAIL fish-loader-order (no OSC 7 seen - loader/driver broken)"; fail=1
  elif [ "${bare:-0}" -le 1 ] && [ "${mid:-0}" -ge 2 ]; then
    echo "ok   fish-loader-order (bare=$bare mid=$mid)"
  else
    echo "FAIL fish-loader-order (bare=$bare mid=$mid; native emitter leaking or our reports missing)"
    printf '%s\n' "$osc" | grep '7;file://' | sed 's/^/     /'; fail=1
  fi
}

have bash && run_cases bash enc_bash || echo "skip bash"
have zsh  && run_cases zsh  enc_zsh  || echo "skip zsh"
have fish && run_cases fish enc_fish || echo "skip fish"
# tcsh's encoder is its stored awk program; run it directly for the full input
# table (covers inputs a real cwd can't hold). The alias/emission layer is checked
# separately by run_tcsh_alias, which needs the real interpreter.
have awk  && run_cases tcsh-awk enc_tcsh || echo "skip tcsh-awk"
have tcsh && run_tcsh_alias || echo "skip tcsh-alias (tcsh not installed)"
have tcsh && run_tcsh_hostname_sanitize || echo "skip tcsh-hostname-sanitize (tcsh not installed)"
have fish && run_fish_hostname_sanitize || echo "skip fish-hostname-sanitize (fish not installed)"
run_fish_machineid_degraded
run_fish_empty_authority
run_single_emitter
run_fish_loader_order
have python3 && run_cases xonsh enc_xonsh || echo "skip xonsh"
run_machineid

exit $fail
