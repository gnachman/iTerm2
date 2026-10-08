# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.

# iTerm2 shell integration for nushell (0.100 and later).
#
# Unlike bash/zsh/tcsh, nushell already speaks the OSC 133 semantic
# prompt protocol itself. With $env.config.shell_integration.osc133 on --
# the default in every version since 0.94 -- it emits A before the
# prompt, B after it, C before running a command, and D with
# $env.LAST_EXIT_CODE when the command finishes. Those marks are placed
# by the line editor, which is the only place they can be placed
# correctly, so this script turns that setting on (in case you turned it
# off) rather than reproducing them by wrapping $env.PROMPT_COMMAND,
# where reedline would have to guess their display width.
#
# What nushell does not know about is iTerm2's own reporting, and that
# is what this script adds:
#
#   OSC 7;file://user@host/path?machineID=<id>
#                                   who and where you are, and whether
#                                   the shell runs on this Mac
#   OSC 1337;SetUserVar=key=<b64>   user-defined variables, for badges
#                                   and \(user.<key>) interpolations
#   OSC 1337;ShellIntegrationVersion and the shell name
#
# nushell can send OSC 7 itself ($env.config.shell_integration.osc7, on
# by default), but without the machineID, which makes iTerm2 treat it as
# a third-party report. This script turns that setting off and sends its
# own report instead, the same way the fish and xonsh scripts do.
#
# Two consequences of letting nushell own OSC 133 are worth knowing.
# First, its marks do not carry the per-command aid= identifier the
# bash/zsh/fish marks do, so nested sessions cannot be closed by aid.
# That is the same tradeoff the fish script makes on fish 4.1+, where
# fish emits the marks natively. Second, hooks only run in the
# interactive REPL, so nothing here fires under `nu -c` or `nu
# script.nu` -- which is exactly what we want.

# Emit an OSC sequence: ESC ] <payload> BEL.
#
# \u{1B} and \u{07} are used rather than \e and \a (which nushell's
# parser does accept) because \u{X...} is the escape form nushell's
# documentation actually specifies, and rather than (char esc), which
# does not exist.
def "iterm2 osc" [payload: string] {
    print --no-newline $"\u{1B}]($payload)\u{07}"
}

# Set a user-defined variable. The value is base64-encoded, exactly as
# in the other shells' scripts.
def "iterm2 set-user-var" [key: string, value: string] {
    iterm2 osc $"1337;SetUserVar=($key)=($value | encode base64)"
}

# hostname -f is fast on macOS so don't cache it: that lets us pick up a
# change, such as when you attach to a VPN. Set $env.iterm2_hostname
# before sourcing this script if hostname is slow for you.
def "iterm2 hostname" [] {
    let configured = ($env.iterm2_hostname? | default "")
    if $configured != "" {
        return $configured
    }
    # `complete` captures stderr, so a BSD hostname(1) that has no -f
    # (NetBSD, OpenBSD) can't scribble its usage message onto the
    # prompt. `do --ignore-errors` covers hostname being absent
    # entirely, in which case the result is null.
    let long = (do --ignore-errors { ^hostname -f | complete })
    if ($long | is-not-empty) and $long.exit_code == 0 {
        let trimmed = ($long.stdout | str trim)
        if $trimmed != "" {
            return $trimmed
        }
    }
    let short = (do --ignore-errors { ^hostname | complete })
    if ($short | is-not-empty) and $short.exit_code == 0 {
        return ($short.stdout | str trim)
    }
    ""
}

# Percent-encode a path for the OSC 7 URL per RFC 3986: unreserved
# characters and the path separator stay, every other character is
# encoded byte by byte over UTF-8, as the receiver decodes it.
def "iterm2 encode-path" [path: string] {
    $path
    | split chars
    | each {|ch|
        if ($ch =~ '^[A-Za-z0-9/._~-]$') {
            $ch
        } else {
            $ch | encode utf8 | encode hex | str replace --all --regex '(..)' '%$1'
        }
    }
    | str join
}

# Machine identity for OSC 7 localhost detection, sent as
# ?machineID=<version>:<value>. Version 1 is the HMAC-SHA256 of macOS's
# kern.bootsessionuuid under a fixed, public protocol key, as lowercase
# hex: iTerm2 computes the same value and compares, so it knows the shell
# shares its filesystem without matching hostnames. The raw per-boot
# UUID is never sent. A known non-Darwin host cannot be this Mac and
# sends the empty value ("1:"); a Darwin failure, or an OS that cannot be
# determined, sends "0:" (identity unavailable), so iTerm2 falls back to
# hostname matching.
#
# This runs sysctl and openssl, so it is computed once when the script
# is loaded, not per prompt. The result is kept in the pre_prompt hook
# (see below), which lives in $env.config and so never reaches child
# processes or an ssh session.
def "iterm2 machine-id" [] {
    let os = ($nu.os-info.name? | default "")
    if $os == "" {
        return "0:"
    }
    if $os != "macos" {
        return "1:"
    }
    let bsid = (do --ignore-errors { ^sysctl -n kern.bootsessionuuid | complete })
    if ($bsid | is-empty) or $bsid.exit_code != 0 {
        return "0:"
    }
    let uuid = ($bsid.stdout | str trim)
    if $uuid == "" {
        return "0:"
    }
    let hmac = (do --ignore-errors {
        $uuid | ^/usr/bin/openssl dgst -sha256 -hmac "iterm2-osc7-machine-id" | complete
    })
    if ($hmac | is-empty) or $hmac.exit_code != 0 {
        return "0:"
    }
    let digest = ($hmac.stdout | str trim | split row " " | last)
    if not ($digest =~ '^[0-9a-f]{64}$') {
        return "0:"
    }
    $"1:($digest)"
}

# Report who and where we are. Runs once at load time and then before
# every prompt, which is where the other shells report it too (zsh's
# iterm2_print_state_data, called from iterm2_after_cmd_executes).
#
# To report your own variables, set $env.iterm2_print_user_vars to a
# closure AFTER sourcing this script -- the commands above have to be in
# scope when the closure is parsed. For example:
#
#   $env.iterm2_print_user_vars = {||
#       iterm2 set-user-var gitBranch (git branch --show-current)
#   }
#
# The username and hostname are reduced to a safe character set, so a
# URL-structural character (/, ?, # or whitespace) cannot restructure
# the URL. The username keeps @, because URL parsers split the authority
# on the last @.
def "iterm2 report-state" [machine_id: string] {
    let user = ($env.USER? | default ($env.LOGNAME? | default "") | str replace --all --regex '[^A-Za-z0-9._@-]' '')
    let host = (iterm2 hostname | str replace --all --regex '[^A-Za-z0-9._-]' '')
    iterm2 osc $"7;file://($user)@($host)(iterm2 encode-path $env.PWD)?machineID=($machine_id)"
    let printer = ($env.iterm2_print_user_vars? | default null)
    if ($printer | describe) == "closure" {
        do $printer
    }
}

# The pre_prompt hook is registered as a string rather than a closure,
# so its text is also the sentinel that says this file has already been
# sourced. The sentinel cannot go stale, because it *is* the hook: if the
# hook is gone, so is the marker. The string also carries the machine ID
# as its argument, which keeps the value out of $env, where it would be
# handed to every child process.
#
# String hooks are a documented hook form, not an introspection trick.
# nu-cmd-base's eval_hook has parsed and evaluated Value::String hooks
# since well before the 0.100 floor, and the Value::List branch recurses
# into each element, so a string inside pre_prompt's list is exercised
# code. The earlier approach -- reading closures back with `view source`
# -- leaned on a debug command whose output the 0.101 release notes
# explicitly tell scripts not to depend on, and which had already
# changed format once in 0.93.
#
# Two consequences, both accepted deliberately:
#
#   * The string is parsed once per prompt. It is a single command call
#     with one literal argument, so the cost is a rounding error next to
#     the `hostname` the hook already shells out to.
#
#   * The command name is resolved at each prompt rather than captured
#     when the hook is registered, so a command that shadows or hides it
#     would change what the hook does. Hence the deliberately private
#     name below: "iterm2-shell-integration pre-prompt" is not something
#     another tool or a user is likely to define by accident, and it is
#     not part of the interface this script offers (that is
#     `iterm2 set-user-var`).
const iterm2_pre_prompt_hook = "iterm2-shell-integration pre-prompt"

def "iterm2-shell-integration pre-prompt" [machine_id: string] {
    iterm2 report-state $machine_id
}

# Has this file already been sourced in this process?
#
# The other shells answer that with ITERM_SHELL_INTEGRATION_INSTALLED,
# but they set it as a plain shell variable that child processes never
# see. nushell has no such thing: everything in $env is handed to
# externals, so writing it here would export it, and a bash or zsh
# started from this shell would find it set and skip its own
# integration entirely. So look for our own hook instead: it lives in
# $env.config, which never leaves the process. A type check keeps the
# comparison honest when a hook is a closure or a conditional record,
# both of which pre_prompt also accepts. The match is on the whole
# string, so a hook that merely contains our command name is not
# mistaken for ours.
#
# pre_prompt is a list from 0.101 on, but on the 0.100 floor it may be a
# single bare hook rather than a list, and `default []` only substitutes
# for null. `any` accepts only a list and rejects a bare value before the
# per-element type check runs, so normalize to a list first. On 0.100,
# $env.config itself only exists if config.nu sets it, hence the `?` on
# every step of the path.
def "iterm2 hook-registered" [] {
    let hooks = ($env.config?.hooks?.pre_prompt? | default [])
    let hook_list = (if ($hooks | describe | str starts-with "list") { $hooks } else { [$hooks] })
    $hook_list | any {|hook|
        ($hook | describe) == "string" and ($hook =~ $"^($iterm2_pre_prompt_hook) '[01]:[0-9a-f]*'$")
    }
}

# Don't run in IDE terminals. TERM_PROGRAM is set by the local terminal
# but not forwarded over SSH. LC_TERMINAL is set by iTerm2 and may be
# forwarded over SSH. Shell integration does not work under tmux or
# screen unless you opt in with
# ITERM_ENABLE_SHELL_INTEGRATION_WITH_TMUX.
#
# ITERM_SHELL_INTEGRATION_INSTALLED is read but never written. It is a
# deliberate opt-out: someone who exports it is asking every shell to
# skip its integration, and bash and zsh obey it the same way when it
# reaches them through the environment. Do not "fix" this by clearing
# or ignoring an inherited value -- that would defeat the opt-out. The
# double-source problem it solves elsewhere is handled here by
# iterm2 hook-registered, which needs no environment variable.
let iterm2_term = ($env.TERM? | default "")
let iterm2_term_program = ($env.TERM_PROGRAM? | default "")
let iterm2_active = (
    $nu.is-interactive
    and ($env.ITERM_SHELL_INTEGRATION_INSTALLED? | default "") == ""
    and (not (iterm2 hook-registered))
    and (
        $iterm2_term_program == ""
        or $iterm2_term_program == "iTerm.app"
        or ($env.LC_TERMINAL? | default "") == "iTerm2"
    )
    and $iterm2_term not-in ["linux", "dumb"]
    and (
        ($env.ITERM_ENABLE_SHELL_INTEGRATION_WITH_TMUX? | default "") != ""
        or $iterm2_term not-in ["screen", "screen-256color", "tmux-256color"]
    )
)

# pre_prompt must be a list from 0.101 on, and defaults to null on
# 0.100, hence the `default []`. On 0.100, $env.config only exists if
# config.nu sets it; nushell fills in every setting a partial record
# leaves out, so starting from an empty record there is safe.
if $iterm2_active {
    let iterm2_machine_id = (iterm2 machine-id)
    $env.config = (
        ($env.config? | default {})
        | upsert shell_integration.osc133 true
        | upsert shell_integration.osc7 false
        | upsert hooks.pre_prompt (
            ($env.config?.hooks?.pre_prompt? | default [])
            | append $"($iterm2_pre_prompt_hook) '($iterm2_machine_id)'"
        )
    )
    iterm2 report-state $iterm2_machine_id
    iterm2 osc "1337;ShellIntegrationVersion=1;shell=nu"
}

# it2 CLI over iTerm2 SSH integration: materialize the embedded copy
# (named by content hash, so a shipped update replaces a stale one) and
# define an `it2` command.
#
# nushell resolves command names at parse time, so this cannot be
# skipped conditionally the way the other shells skip it when it2
# already exists. Instead the command checks at run time and hands off
# to an it2 that is already on PATH, falling back to the embedded copy
# only when there is none.
#
# Both branches end in the external call, so it is the command's result:
# `it2 ... | from json` and `let x = (it2 ...)` see its output instead of
# it going straight to the terminal. Failures raise an error, so a script
# that checks the result sees them, as `return 1` does in the zsh script.
def --wrapped it2 [...args] {
    # --all because without it `which` stops at this very command.
    let existing = (which --all it2 | where type == "external")
    if ($existing | is-not-empty) {
        let it2_path = ($existing | first | get path)
        ^$it2_path ...$args
    } else {
        let python = (which python3 | where type == "external")
        if ($python | is-empty) {
            error make --unspanned {msg: "it2: python3 is required"}
        }
        let py = ($python | first | get path)
        let home = ($env.HOME? | default "~" | path expand)
        let target = ($home | path join ".iterm2" "it2.4a5c7f87cc6e339b.py")
        if not ($target | path exists) {
            let blob = "H4sIAAAAAAACA7VbbXPbRpL+zl8xR1/OQEJCspLcbslRqhxbjnVrWy5JuWTL56KGwJCEBWK4GEA0dzf//Z7u6QHAFznZ3Tt/iIi3nun3p7snj/7tqHHV0TQvj0x5r1abemHLrwfD4fDKLG1t1G1en9yqtMhNWauZrVR+Y6rlibq+fqXysjbzSte5LZPB4OeFKdXGNkpXRjm3eJzRC1ZptbCuVve5lm8fu92vR6peGJXaMmvS2laP3WBW6aWpktVGmU8rW9UOZJoy/6Qyu9R5qZxN70ytopWuF6Ck/v3i5mRyffn8TzFI6VqtKvspN05hfZAeFDbVhSyfqJtFjid5uVGuzop8OrZlsQk8fmwcM7rWVYZVq/m9+krV+DAvQQJ7rM2neuDpKk93qdNFXpqRWi8MeKcHX1ZGF18qCA+fLJe6zFRdGaMis5yaLDMkG9lPrKqmdAN6JcsdGEoX7cbVs3cXypnq3lRPabO2qY/wx1TVkfmU17iFdZZqqtM7YssEJkqDLwbTJi+Ih5LJVOYvjQFvee1MMRtBhIop6A1Wq3Lop4AUSLabMlXrHIKlHVyv8xl9dEIqzsEeRFvb1BYqqkmOsuJ34++VV5roJh6pwpTzejFeVWaWfwLL/NydDgYK/94/UdMNDKzerMyH99/4i2k+H5syy7Hlld4UVmdC5MN7uf4wGPy0ErYjWRtLiyhPmfTjV4/Vq/PXry/x+6Oz5an6W2nLFAoidY5Uus5GrNKRyp2u6w1u2cKNVGXX7ldP4vlj9fzZ2+fnr5Uyy1W9USq6vvjx4u3NU9U48DLdQPnlfAzdlXk5P1raMofpBm27eDB4Yddl2Kl4DXbq9xx2evlYXd+8uPzpRqlKr1kIzj855yfnV1d7T355rM5/ubhRHXepzcyvuIwKTcZLYn5KplqalNyL9FhiYesM7esKhgBFOsVmTzp+x25PtlBmMHsFn6h0tVFkk/Ls6+QPX6lo3uhKwwMgAGjVgZHTAREQzbNB1Lq4Y/vVBXjPNmzecF5YLcwoTii4DAb5ktyaGQi/rQu/XD6Hs7VXbE/tVV0hSLRXm/ajOl+awcDr/UxNh6+GA9EgXT0fDkTQZ8pWWTS8HMYDEbDcOccdFqxc/4LrwSP1TGUmLRDUxIDFIpWe2nvjWSauwWuNVzRFKh8W6G2YBj5nj4q0ynStvaEvc0fCAXn/gSfpPSVmuYN8BYIwSoQ4li2coq42RBHCnTazGd21FKdYid+oH/MfVPP1CeLRp3zZLBNQ/9GUprINbHtqUg3L5cXmOYSF7SKarsux5yrVVZWzURiFMLNqapiBD2p5usDjEiQU5DCnKJbMiTolB4Qn58jIiJ9bZWdYAcHHuweTiJ/y/sSBx/QeKwurgGRh1yw/vEExk4ywKECbTI3clOTLMXme3xsOZvlyaRAiauwtLYyuFMIhPI+SE57a6X0OhmHZUztvnIg2Gbx59svk5dWzN+eT1+dvf7x5BS2ffPuf6kv15PjkG/mDZS8RJyhlYZMQr2ieVLQdj0YURr1TKrewTQGFQX73HB4RL4pNoi5mgSvSM/PloPhsHEiRRbBtjJTfe1NirZUtHRMypkIQJUmRQtgoXFPNNG2wFKZzRBhPH4Kfwu7uyD4gCkoA0CU2Xpn03ifFd+fv1Dd/+FbdGbNyuC/WFHkN6wIZwa2xS0RB3vksr1wN0s/rqhg/jyVxZgbhwcAqDWScWQjg7eWN0qsVBROftfKsMGqtc48Y6E6JpOndB9lfhDseKw3q/TCqbkMcHY9nlnZy2zNXSk+gDLmbem0Q0nxCSQbvnv359eWzF5Orc/zn5uLNuffzr4/Jf2+qxpARFz4zM3yoF2yF5LoQdga8gqwzYXIJ5zoAD6RixG9VWnnbccokEhQ3QXhlYfjTgjSMpAVhBjv2iULBYbHbisRIrHEcxhuOvE024LelJbDkxBleJWsBwQSfTBAKAZQUMEFKUZUIzAo9Z2uABpsKW4QPQDRrCvIQOS1h6pDfGQnIDk3lPGlhlTTgdY9v1osN8UomRJclYrzJTpkf+kJ5pCVJg4nWtsG2OBUiaICyZ2rEe2ODEy539oBtJYMJESWxnKmXsDxE7kFmZr3NRRT2R2pG+GAUvO9sOhxK6pwXdopwEejwvXyGHZJLaHhxJN+MKGXIR/QveN9Z+JWYkhJoNGzq2fiPCPr0ltjomd8AIKDPO8kKUCsafn8xZHgT1oj9R4/Utam965COpoYcsROhmI/Pbq15UGT1ErJThnpqWNpaCV9DIewtZW0YXbMFUxLJyNHg+esKLgJhiiUl/FFPxOQDfA9W2kmCJJzQS/D5SBj+KkjFczQj1Fv0vnlAbxRkJuaTTmvRGzB9BooU/8/ewjxEAY8oKt6GJ7cUAinAJXB7oMoyT6OYb0CFy1VM9kZhXwqEn19dvj7neKqWjNLzMncLsj8COGEBAzTug97c1CGxkNfTrqdNhruUdCl+SxZiX9HKUSoCEk7vCkqHJWmBQqUipFPXwcgeUTIw1ZiX4EhHZKpE/QzIzIG65dyrm+ELwl7aVBXB1ZD7KGRSxo24+IGY4RuPZQnRBvOKHEeZD84MIGUY7oZIH7JzTsvNd+Ii+7CLvTGki6ZEADlT7z/wdSeSM1XyHW9h3f3v1XGndnhWyxRFB4iGtNq9QP9EuGfdq+M97W59AKryzXdn/dXCv0rnLggwEbFFw+DALJx2KfMp5ZA13F5CbLwOX/v1undYLtgyv0cqjVoJxH3uiWN+d3uXPgSzLLZJugTqhatEfNWR6uQ7PuMI0nsuxBDjko82l0eE2DsX60Jj61BU9vXNZaF90hIrQ9pZNRVylTl9wExYn9WSECvBECHrKxd6PRSw0W5ujoPjELQxGSd5QZOc/NlJSXCMZZPtuLoXMb6NQwyXd7CvbRvrCXvUidwH6DP56v2xt29B1GchbjdlL3LLq09Ov/0Qhw+wrnzzvdrFit0WzAq5HDYIjHDaAnwPxaLDZcIXmZimC7gceJgFgk+T/ymH6gt5Nf4NRsUK/ct7UpFECePp2UWbApuyyO9MC8V6Who9gF+fAj83ZbYbeKkv0IZB5No5YkbwwQS10n5kJCNc8wpT40MpRWzDNQJbeC/8jiX8ygqhcnIwziKYq5ROFMNDJGAcPvKRn9kgrXzXxVld1bHswXdGxMQFTQMGEZdtKGHGfeaoLWxbtSULfs1RlgCDOkq7PnjAsEiVTLSlcbaf175Sh3DqflruAMqej4Tio02t4Ye3HTK0Va2i7Yg5Ujf+xznZ6UhdXvOP+PdZdXBukoGHGF9kY65hvQ0FuPCbRt2x1bnuLrrYksOh8M1Qotu351cY2v5ypZ0LbhOW/p0RZduj5GOJwqETCGD+VxO1QdhtXOL7c2ERj8e7e9x+yQImNJ9M6stoX0TPrFXf/8f4lkPqHs1khtRcWtgQZ0SnntVwlGlTG2ac/E4aTbJKXo7hxymZqf9CSP63LhojZkAh3XJrQb6d6bxoqNgVeYJsuSEzx0tIw0ujUWsMKbWIDIbJAUwJsVADxSVIs5NtaR1gaC/m0YtJaotmWVLBRVdk327LvrfZby161OMv3lPy8UgdhypDz8wE+0vXWafCl9jSW1u/JOc/97YPZB6chcyIAsLaVlxiZzmcE8kQdZemWnpp7012QB6yuJcHrzf4nOXK69Qh63bqm5QHjW2pNxRW2eCifROLCSxuS+vpvo0IWbzaye+p2EZrFHga7OJBLnsKDnv+rN765rgflYRoKDNQXLGdOl9bLjR13/QdnExTUqTOJ0nBNSnxNGsKroo4KfGPwAohIry04OaDmH5OHR5qzYSGOv57x/2Zroeb2tI1vsuJBan9DiESFq8sbWKVU7BgAPVIYfWCuvl3Mo6QFOtqu1LUk6JcfH3x47uLd+e+SeM7hkSDrP0pFXLdbrVsk0tsHWp6skTsIELYGKlDqqduhC24U5Oxt2eVBSblzOlfRBneOD0tzMSJaM+odxAFyMlym1R6HfnnbTBsTfFKWhDcZKmtr5fm1reVKlt7kSx0taScSQ0j2QOzxYyM/RaEx3gU3JHUHryuVQtEHcpoXzGxTLcleigq8feJb5omzFa0VefuvzQrGrfo1Ss7kkp0lkV5JoLZj2NtxR1s/wc2k3fQsBj887Y/f0WgaNf6qfHcMy11JNjJh2Htm6WHzBOW6YLG11Rv6jWChG/ZdsQ566TLTP2d0bAap8e3bL1Q8RxU/tIAwJNVcb9Z2piKuhhiY7ap1MuLq+sbbyVxn/gNNcO9rZKtsdag6tJPlZBBgDew1q6rEhDjqLOmso8WDULv0Q6WujBNBUbzVHrIHt4FcJjzykPvKZ7IiG2vZ4tDyi9IQwC7Pfrw2hQQj6EOnNi3wkfic6H54QcLo14XLogJRk/YiYZz1FRKDkezfz4o9kMWR/2jAzl/h+ZRLy36EAUd4G0yK1mhR59d6fyHZy9eAuHZpbolXNIuM/bqH1OISdSNxJfD8aoXrXr0Q9wibYx6AQMIknuLmsYg0sMfz63NVD8ok5y9yzduT7idP3KllJe7XitxTfAuqgkHY2+D2TXhWRLqkfAa2GAuaTBABTIZPtwOhqLnpSULdLtI7oSh3KE45BMkoLUEobCFf8EiGOh6vqi1EGACIecJN20ZjZnyPodpEgqJhmFYPoz7hWX7xQOFAb0T+vQyzjt4FkBFgT4ZKfesYqoJ9mLkyeBwT1LaMahg/J9Qzzx7Ofnp7cUvo/CUlphc36CaehNvNzVl9hm1LB1CXRQhzAO8Svuv4pJS2Iy+cPGp+sL58qajjcIzPsBbb8E/mc3UIqhcUP+7alb1Hsh5QrMKbh61g2gqIbeLDWmgFIXFs7+1JIY83B6eHlTz20tEKkS64VAyK39Bc3B8QOZIP98/Of3QewqYSg/7ILn3lDZ1YLGb86s3e+t4FBiIBUzYXwrs4jFz3d0l9nGX/vi7vx4wlN1JAU9+RzxRTrJmuXIRiyr+h1Xfzc0RBepO4+b/TMlUbFTAq36whs3cOZkSVH6wQvaXmuIp5XwUGSG5wMd1U9Tt6ICxQNeNMXSCJhC9y2ncWHdnQih2EWjw7RYaNuLjtaGGFUG0hgIrry8Eu7nEEiibj7I0ZR6Yo8FXaHnMukFVRH/LBkjR6ybuV4Y09kj8n0iu/KhspLrLyYuXr+NDDNHkS9e66HdlwzRiu/Qn6NRO1MIpBJ6s8VytncRFYR4Yh0kVAAhHcnrgwdd4hzInzTAL24YDibqWaz2nIWPZopIw+vL9N7tHtDI0P9Rl3Ru1MWCn7g4FxIhPlrDg/YC1HM+KfL6QmWqMpe/yFXS0KwgRKG3Wm5KR+ZwOx1t6IrIlT0UILsqEibeTatfDMZ09P9y1edTrXHGJysVaYWY0HEEtVNWHTwO0I9IF91F9mH/qp/w7C9DRJevf9ow89uogzMbjS4ZrfprtZ5R0cqAEuOS6bWtZPwDfWcBrLgBEjx1JJA2chIY57KC9uXIvbLBI8/s+Jv7tXtbBmOZZ+wcaXoPf9LTWVeOBRK+8nhBURU459p/r9YQB7FkPrUop0r/leadCp9vIds8stDB7U4u+9/rO/V5Tzi8HrLf/7tmZHJc63Z0jUbbulattI2K3ZN1eRHhqi7WHt4C6fHsT51dXv28TiJf/P5ugs0o73dJOc3vU9pyU/tnpR7zLKZO250JRnGRmayQe7335qI/9g7oZ70Of9zD/TP3X9eVbBRjrR0B0MucjHESwsj5AcUqzbSSPqamOAL3pWF3ZFAVAF0GMEEt5JrjTAN0j1rdqSktY28MUugeYchzHO6cF8AYqxDytY4gZKxwPtul5aN6H4jeb1V6v8dD6xwcsO+Bur/3tqn+3/JHTWFs9kF6vKnqgCUCHx3bLOq5Q2jHeTIr/WykKu65Vot7kHiftdKbo7K7vsvT3DABzEL9wJQgc0h7vkVHiyJ9IZFN9cvLHr4Rk9OTrXsjcnwX8y9Hx82MGLvqif4JcgHffPHmgoNki/RDZLn6Heky8uS9pPp9I0wRLgCGtGz60y0eRe0c/NXcxfELingvPIELviA5EdxTDdDeDx/KQ2y5XhamNzIRBPRK1ppV2KHYIWCKDfrTTkW9J9XT2EJDebk/KEnRs/HBZ2LtoHUlK3Aln5JQq+kyq+om06kIZLydW+S4dz+sfm1ZZw2iacSwcjUCZWzQ1+RCf2DvY8hXCvSp/34diHryL3/lIyDtQi1xOoQAPjvsdPUaJAb0T7CPZUWvPrbBJBAA1PGdbYUwxLwm8ETBLkkTtdBOHiqzB0Dnwke+0kc7nYVLr+wItzvPlQyYolzrdvlfIZ4uIA3ZVgK6SjjG+ZC64EBaxgJHQpRWEFQoU042WVpbOrRHvs4w69EeZuedw3h6DErGLmPxBdI+3kiDwayMza/pfESCF0DMXeCqazmzqEjmvZNtxFt7ZwgFdOo4/N3D0TeDd7u+DXdzP92YeTrwONerqJMJfuzIl/YV8SDwjenY5+fnq8u3rP8ejdkN7A7P+tg4MwEY7OfJAkpLOEdVRkxKBYzIhWDGcTMheJpPh6X40k5TmDep3Vr+U00IN5/VWauwIxVFewgBCVBAj5YRMpSuZzs5JSiqD9Kzmg+SDfrHBlY1TbfnIfRtDTWIQ1s6Xu6luqGLa22mizikRaW/yXKXvpE0qWgzSWFv98vl332uVE7g0J6Wugx+Rt97oO97gqIY7P0l25RjW+kxUG4S+ITlmRN/Fg/8FpzpKV7YzAAA="
            let materialize = (do --ignore-errors {
                ^$py -c 'import base64,glob,gzip,os,sys,tempfile; d=os.path.expanduser("~/.iterm2"); os.makedirs(d,exist_ok=True); data=gzip.decompress(base64.b64decode(sys.argv[1])); fd,tmp=tempfile.mkstemp(dir=d); os.write(fd,data); os.close(fd); os.replace(tmp,sys.argv[2]); [os.remove(f) for f in glob.glob(os.path.join(d,"it2*.py")) if f!=sys.argv[2]]' $blob $target | complete
            })
            if ($materialize | is-empty) or $materialize.exit_code != 0 {
                error make --unspanned {msg: "it2: could not be installed"}
            }
        }
        ^$py $target ...$args
    }
}
