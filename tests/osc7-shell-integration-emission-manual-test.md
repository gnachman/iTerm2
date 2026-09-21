# OSC 7 shell-integration emission (manual test)

Verifies that each shell integration script emits a correct OSC 7
report: the working directory percent-encoded byte-wise over UTF-8
(RFC 3986), the username and hostname, and the `?machineID=` token.
The percent-encoders are the subtle part (bash's `printf "%02X"`
sign handling, zsh's `nomultibyte`, tcsh's awk `ord[]` table, fish's
`string escape --style=url`, xonsh's `_encode_path`).

The encoders for all five shells (bash, zsh, fish, tcsh, xonsh) are
covered automatically by `tools/test_shell_integration_encoders.sh`
(it runs each shell's encoder against a table of inputs and asserts
the golden output; skips a shell that isn't installed). It also drives
the real `tcsh` interpreter through the `_iterm2_print_osc7` alias for
one creatable tricky directory, asserting the whole emitted URL, to
pin the alias quoting / argument alignment. The full end-to-end
emission and the fish/machineID checks below are still verified
manually.

## Procedure

For each shell, in an interactive iTerm2 session:

1. `mkdir -p "/tmp/osc7 test/ü"` and `cd "/tmp/osc7 test/ü"`.
2. Turn on iTerm2 debug logging (or run under `script`/a PTY
   capture) so the raw bytes are visible.
3. Source the shell's integration script from
   `submodules/iTerm2-shell-integration/shell_integration/<shell>`
   (or install it normally) and let one prompt render.
4. Confirm the emitted OSC 7 matches the golden URL below.

## Golden URL

With username `gnachman`, hostname `MacBook-Pro-3.attlocal.net`,
and this Mac's machine-id value as `<hmac>`:

```
ESC ] 7 ; file://gnachman@MacBook-Pro-3.attlocal.net/tmp/osc7%20test/%C3%BC?machineID=1:<hmac> BEL
```

`<hmac>` is NOT the raw boot-session UUID: it is the lowercase hex of
`HMAC-SHA256("iterm2-osc7-machine-id", kern.bootsessionuuid)` (the
HMAC keeps the raw per-boot UUID off the wire). Compute the expected
value with:

```
printf '%s' "$(sysctl -n kern.bootsessionuuid)" \
  | /usr/bin/openssl dgst -sha256 -hmac "iterm2-osc7-machine-id" | awk '{print $NF}'
```

Key points to check:

- The space encodes as `%20` and `ü` (U+00FC) as its two UTF-8
  bytes `%C3%BC`. `/`, `~`, `-`, `.`, `_`, and alphanumerics are
  NOT encoded.
- The `?machineID=` token is `1:<hmac>` on this Mac (a 64-char hex
  string, matching the command above). On a machine where `sysctl -n
  kern.bootsessionuuid` fails it is `0:` (identity unavailable); on a
  non-Darwin host it is `1:` (positively "not this machine").

### sysctl-failure fallback (all shells, esp. tcsh)

To confirm the `0:` fallback (and that tcsh no longer drops the
token entirely), shadow `sysctl` with a failing stub on `PATH`:

```
mkdir -p /tmp/fakebin
printf '#!/bin/sh\nexit 1\n' > /tmp/fakebin/sysctl
chmod +x /tmp/fakebin/sysctl
PATH=/tmp/fakebin:$PATH <shell>
```

Source the integration and confirm the emitted OSC 7 ends in
`?machineID=0:` (NOT omitting the query). Before the fix, tcsh
dropped `?machineID=` completely here, which made the receiver treat
its report as third-party and add a blank line above every prompt in
Auto Composer mode.

## fish

fish additionally must NOT emit its own second OSC 7. When running
under iTerm2, iTerm2's integration shadows fish's built-in
`__fish_update_cwd_osc` with a no-op, so only the URL above (carrying
the machineID) is emitted per prompt. The iTerm2 check is
`TERM_PROGRAM = iTerm.app` OR `LC_TERMINAL = iTerm2`: the latter is
forwarded over ssh (TERM_PROGRAM is not), so the shadow also applies
on a remote fish reached through iTerm2. Under another terminal (e.g.
WezTerm) fish's own `__fish_update_cwd_osc` survives. Verify with
`functions __fish_update_cwd_osc` in each, including over ssh.
