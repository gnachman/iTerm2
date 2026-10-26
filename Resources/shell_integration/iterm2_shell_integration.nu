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
        let target = ($home | path join ".iterm2" "it2.9ec2bce60a6b86bf.py")
        if not ($target | path exists) {
            let blob = "H4sIAAAAAAACA7V9bXfbRrLmd/6KXniyJickbCtO7qwc+VxFphPt2JKPJCeZ46tDgURTREQCHDRgWZOb/37rqaoGGiQle2Z2/UEWiUZ1d3W9V3Xp0f96UrvyyTTLn9j8o1nfVYsi/6YXRdGZXRWVNVdZtXdlZsvM5pWZF6XJLmy52jPn5z+ZLK/sdZlUWZHHvd4vC5ubu6I2SWmNc4vHKQYUJjGLwlXmY5bou4/d5ttDUy2smRV5Ws+qonzsevMyWdkyXt8Z+2ldlJUjMHWefTJpsUqy3LhidmMr018n1YIgmT8dX+xNzk+P/jogUEll1mXxKbPO0PwEurcsZslSp4/NxSKjJ1l+Z1yVLrPpqMiXd36Pv9WON3qblCnNWl5/NF+bil7McgJBa6zsp6oncI3AXSWzRZbbobldWNo7Hvy5tMnyz4aQR6+sVkmemqq01vTtamrT1AI3up6BKevc9TAkzRxtaLZoFm4O3x0bZ8uPtnyBxRZ19YT+s2X5xH7KKvqK5lmZaTK7wbas30Ru6Y3etM6W2EPOYEr799rS3rLK2eV8SCg0DCG5o9nKjM5nSVgAbu/ymbnNCLFYwfltNsdLezjijLZHqK2KWbE0/Qp41Bm/H700cmh6NoOhWdr8ulqM1qWdZ59oy/zc7fd6hv59eGamd0Rg1d3aXn54Lh+m2fXI5mlGS14nd8siSRXI5Qf9fNnrvV/rtvs6N02tqNxn0I9/emx+Gr95c0q//+aKfN/87hc9NHmRz+iocLBDM7tNh3y4Q5O5pKru6Kti6YamLG7pJ7HEEGjP8j8E8NFjc3R4cjR+Y4xdras7Y/rnxz8en1y8MLWjHU7viCTy6xGdaJ7l109WRZ4RQXsacINe71Vxm/v1Ky/R+mUnfv2nj835xavT9xfGlMkto8bJkzE/GZ+dbT359bEZ/3p8Ydo9z4rU/kEf+8sEJA3kvwAB53YGpsPp5jRx4SzWdUbkQcfrDDMDTv4dCwNQSJ4SMxjilDIp7wwoVZ99E//H16Z/XSdlQnxBCKCzdrSR/R4AKD0wmVTJ8oapOlnS3tM7JnpiaaJlIq5BDJHT62UrMDvRs7PfPfefsB3/e+H8by67JoZsPjHNNZ+qkgRJ86me0vHPrGvfvWt+rbKV7fWEWg7MNPop6j0y56CqjDEkhBR7sce86GRLxGIOeAQ+iiVtZMi/ErUTLUBg5faWdqdEygyV5ASdJNoyyVnw0SSuInSYYm6UZsCUi2Q5F9y4qijS2PxQr9b0gGi1uLa0qrLlz2S9Jnn5yBx56UmS8JVd1Z9iT/M/yzpZPAV7MtckSB1hbkUQMXHSiKpZkudFhRUR4FlRlkQxRBSYkyRQbA4VAi8iL0zkp4pAAGlSMYqIADK7TBkps6LOIcSdYCruvTs7vTg9On0z+Xl8dn58ekLIf9ZT3sI5HEU9ZYEDU5RpPzqNBj0lff1mTN8wyevnX+kzrffQpHa2JCWkAkcliEmmxUcrJwd6JCqsaEiCgxIxjtHAQ2pZAvYTQztJRDCtMgeyJfDygoAUyTbgHRL4kgCS6Ej4gEgNEbLLO0Aksp/W8zm+LaBXGDnPzY/ZD6b+Zo/0x6dsVa9igv6jzW1Z1CR7pnaWEB3xZNcZkSktl7TfbT6SXc2SssyYXa2hQ1nXFTGoKKFstsAREghDeLiG1omvAR3KnEjYMdliP1cgvASULIKLQQxe8PpU4I4wjtmEZiGQy+KW8UcjoOMgHpZLgg0hAGEK/LIOvc7AKbSMbLWyJNIrWttsaZPSkPoimQhjgp4W048ZbZjIa1pc105RG/feHv46eX12+HY8eTM++fHiJzrlvW+/M382z57uPdf/aNpTkuYwMWiRhF49eRxRV38MofZEXBpHRAyyJPx9ZHVGknx5F5vjud8Vzpn35ejg05EHBYpg2hgaWXud01zrIncMyNqSlB4whQNhonB1OU+wwFw3rfxO8AnxU6K7G9AHoQIK20CY0Pyzj2LEvBu/M8//41tzY+3a0fdKTX054WRJGtzd0ipJVym7kbyAKKjK5ehooIZOaklwW6JKSzhOC0LAyekFxAbEvFgZWbq05jbJxMLDNzkZOcI+ZK0pckcjkxD0UMGZK6/hRqN5gZVcBeQKc4IgE95tdWtJ9ogBQMx/+Lc3p4evJmdj+nFx/HYsfP7NU/DvRVlbEPFSLCk296oFUyFYl5Cdkn1JVsKEwcVsm5ChSKYTaVaIIxnt2MQBCGg0ArwuiPCnS5wwGRmETE/HosJJ6ua02hJoxNZYQ9IIB27TBciyEhUsGXZGQ0EtBDCmVyaklsiwNWTDzW5UT8yXybVqhqouaYnEA5CmkMaEckxhK2+PseWmKyS5LaB1qzgBOXt653Zxh72ChPAxJ+1r033eD94wYhmrOmegVVHTsthIIaFBkGVTorWY4HSXG2ugZcW9CYACLQfmNVEe6cxeaufB4vpQwUMzhz039Nx3MI0iNWqul8WUxIWHw99lc1ohWCIhLu7rO7C4Sn0J/zz3HfjfYpvDtOlHdTUf/YWEPkYpjR7IAshkFxsgXpNp3I9eHkdsjvo5BvISNH0lrIMzmlowYotCJR+xNBrygGQVDBVTNgdMBGWp+4oUsFDKrWVvSE0JkiVgNOL825JYhFWu0DC/FKAYPMDfEZW2mACGYwwinu/rhr/2WJEdzeGlLIN37jk3CJmJ/ZTMKj03Mg9Sggj5f3BC5KEH8AhS8co/uYIIhICLie1J4+fZrD/gL+gIV+sB6A1iXx26X346fTNmeWpW7FVleeYWoD+Ynn4CS96TCD0ybbxiAddj1dM6pW+hdCG/VQsxryTGQRWR5zK7WVpvskBUGtigVeWJ7BGUgS1HPAVLOoApY/OLmDMmaXYux82mJIm9WU2GT141ug8iExq3z84qoZl447FOoafBeyUdB81HzEwmrmX3xEt6r50zTHe9IReZh91AiGG2qHMSIAfmwyV/blFyYHL+Riis/f6ledoeO3FWsylIB0INTrUdgH+K3IN26GjrdDsvEFR95/uDcDb/r0wy5xEYK9r6kWdgRk4zlf00Y5EVdadQGq/82zJfO4bxQkvmcTjSfoOBQbh77JjHdlcpIphx0QXpYjpeYpU+f2pBtfgdHbAECZ4rMJJx8W9Fpo/gS7Us1orGhqHgpofkskhEaSmVkdpZ1yXpKrt/D5nweZYrWKwwQxSs+JQY7q34/qZuHnjGgWljU1byak2y8mcmBeLYlo27cnVLYnw78DJcx9C6ujQWIHvYolwE9IG+9eGp0Lda1Adebtd5ILl16LP9by8H/gWaV995aTZtxXYJdk26nGiQbIT9xsAXU6y/2034KlXSdN4uJ3uYEUKvxv+VR+YrHTr4zEaVCmXwFlZUURLxBHTRqMA6X2Y3tjHFglMa3mO/viD7uc7TTcELF60Rg6Rrr0lmeB6EI7ctGUGEtzzD1IoohcS27CMwhQfid6TiV2fwnpMj4lx6clXXCTLcSwK2w4ci+XkbOJXvWzmblNVA1yCRLCVxtabJDMIuG1HCGxfNURVE26ZxWei3a3JLyAZ1ULsiPIiwcJQMtIFxsK3Xvja77NRttdwaKFs84p2PRrX6X4R2QGjryvS7EnNoLuSXMeh0aE7P+ZfBl1G1Z27gQEyMr9IR+7BCQ95c+CxRt9tqWXfTuujgYZf4ZlOiXbfsVzfUfXOdOOfZxk/9hRKly1H6skphH7klw/wftt8IYXfnYomn+knEHm+/48BY6m1C+8nOxI0WJ3peFObl/x5dsUjdghnPSTXnBdEQa0RnDitilGldWd44+E5DgDpLlo80RKVvKMifk2VtlQw4zMShBX13nmTLGs6u4pPA5ncgcxpEanhlE/I1IqgWxUEU77ApCS0IoLiY1Oyki60dG9qSeRgYz4plvcrhcOET6Nt16Lu7/Yaih8H+BluH/HRonnovI5nbCa1vdpu2R/ialnRSVK/B/GOhfbLMPbOAjCAQbouSXew0QxCrIBl2m8CXXhUfbboDHzq54IPn6z1EuTocsct2pRJK3klsq+QOYpUJrr9NYgMYi11svdimEQVLQ1v8vVDaaIiCnnq6uHeXwQH7NT94biE5bkslBerdDHKumE6d+JaLBNG35IaYLIFSREwaWHD1DHua10v2ilgp8S9+K7CIaNCCgw9K+hkiPAjN+AQI/bzh+EwbXZ8Vuasl/kwTIl1CSIQtXhZYxDqDsGAD6pGh2ZfIvtxo+khVrKuKtUFMCrr4/PjHd8fvxhKkkYghYIDaX8CRa1eb6DLZxU68Tw9KpBX0SWwMza6jRzSiWHKkRoKmaVmQTcqaUwaSG167ZLq0E6eoPUDsoO9NTsbbpExu+/K8EYYNKZ5pCIKDLFUh/tJ1IWGlsqgEJYukXEFnImCka+Bt8UZGsgTd42Do2RHH7rmuORZCtXejxWNinHYxuksq8fuxBE1j3la/4+duD5ova7cI/JUNTMVJmvazVBGzLccaj9vT/g9MJu/ohJXgj5rMyRmMok3qR+A5IC3zRG0nEcOJBEt3kSdRpvMnfgt/M7klISEh2xY4a53ZKjX/zdawGc2eXjH10hFfE5S/12TAg6o43qxhTIMohtJYUZfm9fHZ+YVQySAEfoFguNAqaI1PjY46bwL8ZG/QXJusCkOMpc4t3D5M6pEewPaUurB1SRvNZhpDFvPOG4cZzxwJpwiQIdNeQIsR9AupITJ2A/jEtTMy8djUISaWUPhQec4HPySxMAyicB5NRPSwnZBMRVAp3i3N/nWhGIoslvpPduj8DZhPArUoIgpZyxGTlc4QwGdWGv9w+Oo1WXjFylzBLmmmGcnxjyBiYnOh8mW3vAqkVQDfyy2cxjAQGGRBcmwxQRpEY/ij66JITSiUgWdh+dptIbflR/aUsnyTa1Wuqb1L3oQjYm+E2TnsWSD1ie7Vb4N3icQAHGQQPrEdEUpynRegQLdpye2xKbdLDomCJNNahZBfwr9BEWzoQj2e2VlRpqoeSfsmHJ3VRCMKDcqCY0xmXU+XCJzxUVWr+pOWBAxZgWpgtXaISK4hnxDrpg8NSMlA7pv/pP1O5MPk+4X9xLYiwPmqAcLnS1Ips+bp/z0/PXkZm7/i0MWqzHLWwvSZZcMFvX7ULPUxCbqUFlaRPDi+2DsSsBr91I0l67WIOrxOC6K5OX8JSKe3Oe13ka1jh6qDYVBjwQlEW8I1FBMXJjoz7MXb979OUP5x9OZ4fHIxOX13cXx6Mnl3Nn59/CvtJgq3HW0NPxsfnZ6Rd3f4I8bOJsj/vk3KG+goV43kPceJMee3MitWU/qcktSFV6zpN9Fzdz4UOeWKljnXBbAX/ghmxe1Izkgh6vJ1LW+OT8bBwoFCftCuSdIZll/GeXkxplQhmT2xt4plqgmIdZJ7PL07pBnOx+dIue6YDo/1qbdoAXnC+5wk5TVpLMKGOqwT5BiGDF7pO4oirphhvst1WVn+kY4Qm5b0xAZdOjlmJWPFjohqDpYKV4b7k61dYd4rcnhvMrZQfHa71IinrCuWahPSzQjERy8i43dB4IiaOFftyzNwviQMUSjDRSL+RKFYyhrZet6VrJsLbsQtRjSOaAQp2TtR9FUyNTNSXckMGZR9WT8n30TQgZRLRFaS2Y1bJsTcltTYWkgsCaBCmHK0QqLCQsUeEZwGYmtaA+dqY5UcWdGaqrbcg0YieUFrqrnWZ71ENCWrxKFgKiFEBQKGh7Ph7qAUaF/t2QnTj1bEg+1B8rypBnRkG6+OX78enxERd8+w+MiFH45Fs6P9tytVV9eXoQDjzbRaz+XX+9g1ALFU8Bdnq5QWBY8rhLij/6o0SvvhHo4bmujR74pgSMI/ovAb3e8E+6UnW6Fv/hcMl/KCLgxd6h/RpegPokSO8EfADEaOzmHjhLwVhUKIh7ymn7SlIWiZfoQihZ9fR5dtGCWMnfBsX2M6fhG1ZsvkbqQajd9d888qEp7escmHZcjXwPKj33Wbk4y2fxkGaLAClSrEec5OWLYockrRhn0Rpq08uWBbVjQlCX6vHlUsa44GZkhAIhtaEnU4nH4qXaWM9A7zu64wVzFe7JZ5YA1Zhy9mYQpFClMZSLUo8rlVtgx4hVhayceAfDR+qsCYLRGT8FlXjkyYvofqN1ySkEB5CXimyy/eR2MPMiMbBzHtbhVKZlOODnGhD4NdJUsIGMtBNhWh++2qMtbkmSu03qtJDcCDZzdGdXNxU6991YCkpexyOVLQRc5ZrU8VDmWTLz16Jgn48/c/vL0ZGCNw12UYR2eHD4sfyfPvEJMKfQv0luKUbHxASUq9Qn3tIncuVDGXZrOqkU/BEtj4x2tbs0KdiR5XXT1sagNmPg6fWgnN2dTrBjEBoJGYbGPi5qxim6I/6OQBOdLvKjKcHMyQ/hfwcDTYjM12tiIQMV8fg4fm2eDDs8sYmmq9kTHEOWV5bT+7oB0W0M6lcEmZ217EVqISuToZPDDfm+fbycqtpeEfDnNoQmFPn7RU7EAnp70O/a977a/fXHYgPTKHU1SFcB0JjrsiR4NOms9uSyW8kGpM4jAuxQMhlHZOfocEBjYgS1oIQm2kxFqiBI5+im/NJZvgB69h44ew8/LAfMtMrht5frkDWZ3lfgCaLluEPN/aOhx7DkXsUJ+mz7kk4IIRw86da/Y+97VVNzmtfAOwGEUs6ZIZvC+bejc058LKbEZs85SY8TcSjm5r3511HJBZ8DT6QsrYSnVsyLAGJ/BUlWS6RKnuYusdfhm8p59lKM4y7mKq+7yiDZ7agin2xBDFI+Tyf8SCPcfBAcvwtB+ZgOn8GP5/SxJseD58Xn+vi4oL9eRVDT0g7YocJ1uAdem1IiznoZnWYg6vA8AeTH6HqBk0beIUGtnf+bUNaEDpnidkst/jefjzh6eXoIfH0ePgu9Ez/2UXYZ3dfni2T+M2z8Mj4t4Daf3Oz53GFuWxxjmQLGqMmA95631B7gds8DNnfzmIU7tdQdXGZliPHXDddYyQq+tvEWp3bsHDrqnDXW7Pu5UZ7Iehk/d5htGv+J3NKMp9vBDUk8lGhqyRB/s79ugaHpPPGlY6EXNRDQ+2Gl8Izrn2t8osR7b4poN4KKWWP3gtzXFOoTt+xsrDcX1wP2BxRNPuDpbJapomhpzj/qjD/6Ra8qZQ7QLqYU6nIfVq3uTZcIweDgGYU/GpCsf1UgrZe4Gw/tSk6djSuSYdveOmEX7gQ73EW7Z2c4dq9yhv0qGtkwruFwsHy2eZT+uJaIG3avTOxIjP2rljPYcRHwBbyN7ERHVdgdqnmn5IfHPYLYxk+SvZb2dxr6hrcfkwMk0seUHrz17LHODwsx+x5T9LUQLX+6H0jxbc33u6993o6f8Z7f1FQ4iPel4LEiVyqoSOnq3+PNySeAlMII4jRCS92IG+Lot67csyrYTYHd/UIQpU2HNaIgcPOpY+l6N6f0CiLa0dIYcLl1kuT2ku8rrINeytLqPX8i3LKBHH2Ee/S7NPWat2rANkTvv5AJKzYzhaJIiedUqnPjSMeMl6X0IsyjKQpPisYy7DgFQTZkw3/cd7PccgBrmbe5RNCEGf8x4PeSCtjRAPC8tfPnuCX05OT47GEooPTH2BJURKz/7B+ZKVN/R7ks9KICE4rnQnAofHSyaj6/ItuFpNVs7vKfcH04iTNa8QCYZk4mIbXFRAeEhlGxbpGTwMwIgJptgq7TKp8xlq6IX62A/UyEzL2laQwt5icseDOLWFdC8Ra2zOCyFvxsjo6CiIcYvDJGFu69q4kBAqQPK1LanJbuWOekl6jM6zTHMrTSrLyEd1GhiUQxQ56EnjVuThfc47woZCrfC+hRhC/7UUoP5sV/7+nr+aI1JKy6txIaNRLZbzEq5B3QuJdLZhvIoveDDOEHjmEArMdL6YAOb3Ul/JFiiz+cesLHIOcGIupVif9/1wKViTKCSX0vNxaNl/G/bTCHbibmBhJ+TWp9eEDR2AcEBDCjCzVHBykpKWh5I9nBczgJQCdZ1/npTLTnTBLDQimA/RIKyew8CtEgOtiX1k/oQXcGjR90orCJu9HH6v61xnKX9QTZS+jPzdlmrBVCqXIZkSk8xrRA4HO1+RT9B5c+KdBDXibw7PL0x1W6gXFPc6/ikW7v3TYbunrlv6zX1bC4KACF4ONXap/tb+aO+yg6Vg+H0QN+o/XL1E2KW9GxeXdd618z4f+d91fBxaQByRzLtuBFEqTQ6CKZH95wuWpKDC71+Nfz55/+aN3r3c9aS7UKGwg71uWq6pMgreP29+vad6pSEtjhByeN0KS5A4Bs8NJTMu9RBF/g9bFpw+jrWAk0SgZIVYnfhslRhMCrpNiAQFuTAjfWr4Tw0iiUhvrCokTlLrlCLqpknGBcKQbd4yYgOlWpTFrRQStNZiI/HwFe6gZLa9mdrcy2RvHJUyI+Pz5L7EmDfHkmxFE+IKS1OuwDe9UWumOiMIo0WxYVw7sjREXeG4W4Ot18nj27Q1fDhIXHJ0kj08jY1UbSIFO7rOUXQWWhX3B5eF7n3NU9cbIZItLRvDcEzE1lCdOKmKSQbTfq9PojHN+IZja2hoZYiXxmLdNQM1v8vRChc3klg5SS8kD3D6falr5ELONnHVAspcG6Dl9GkEGBHjK2IwhOsfSJvjVG1rgrCt7r0hLVdMvHLNvI+9TrJSU5U7bILHThYqYXDJatKSNcwTyCyD+DXHnhQdHP9tNvHiIYXVVLYTbYnyCnWGlNS26DgIj6f5OjwhLyKdXpJ6oJi0eUvVGrTXQfutyDfBcceClUX15YWu/6k3zXGbSWzfCBdUe3LpSDPJ4e75KqaWaqhgmBXrO6EfYo/kurQIdUy5QlssSVwBER0lOpugoxp6JrJKzAUy2hdx72w8/nV8NPnx/SH54yeHb8ea8p3Ig/GrqLm3gAWwhG9xOcRZqdSnNXeN7CadyZfM+KKU3rNtBB19z1YlR8F93Zm/RMhj2QtRkm9cxK6J/e5v95jVbFDnYtm0JnNgLqtpLfTAopp9OUKuOkF8KxkLlDvbkjZpHYYc0lTlGR8NG2WzoPAhyBSw6S5SVq8mHl+ch6up14iqSGFftEZdkyQ8+SZrMA6nCuM0bwxDti7ljsdar9BrCgtCPDY/B1fSA0CJWCy5gmtukSvCTzV+mkxdsawrNY/Y/51n3nhlW94N/W0iudmYoUyrydayfOiwrNovG2xEW+5YL507gKAwZhkcRoEb/zG+RIHq1PHzwU4W9gCJOnmWLXp/4LWObUQw/JxI5TMf8LRwaLeeeLYYPHzPaMsmeajyefMGSYsCIPxzOGiUYLXocLTiVhpfdHj4TNSeusBak8Z64ArvXDWMeoWXr1od5jOgXB2PgjLyXv3RE50u0wmayhxwBK6PKbtPPmydEWJx0TN/I+ZcC0eZ1q20gfHdS7wPKiLgsVMbiiORQ696yAGLN6aMRJBEl3yfVO/GhALsgIu+sKNagjdEh5H2xYm2qaWQsR9tPwAyNB86nzDRpfmaK4r6wOFg2C7p4QJzrRbbMEZ2arvmPN+gInDLdJH4ub+DzLWPEkUL8tA+p7LfmifyeKDBzA0bxR82lPVELqCE10WKMrRe8vaDCze4S0SwYbN1oe9BQdF1fnbGh9kOOPAXFOU/f/nm8PXk/QmqQPQz4jmT84uz8eHbwWfuuyiqhTHvuewCWb9x/bKDtOgrt2++criIo3uzg8/nn2R6OA39nbmmnTdtOrdt7sVVx77pWkcdw6ndhdb8pxlrLm2hxIVZILOwnYpcRfIONi5AokOGXuTiUgVztEzq1JojMtAJ6rvCVRdFsXzvmgtMXPAjFVeJtrmoaIS6tlq7Jb0+rrWphtie0pVGrU/+gCYnyRojn31n3mY/DLmIQRuGoGwB9wvPL14dn0x++NvF+By9SoImFD25u8fC8GNSZpAajjsCcNmDNp06zA23aoAMEPHF2pVYc/8+SxANuLhqEKuRYP6MTHQakSVoUlSh2tyx/gXJhBctcnQccagGwDuF5GJVKr5NZo2PhYYm67Um3vjmmlRdObbSkjQtASHxkXM0EZEqoGFbC2SMb0vQ2m2K+iHLAIkLCixpl0AwxmdvmwKE41eAEeQvfAWEWF9zqUDG89+KqaoAhsKB1/fHF2NPtU2DBHVDVVw0g8mEbP81g0P7VQpLt2y13iHR7S/jV5Pxyc+sqkAFGrAiz7ET+djYG75qFuo/kAryTiaThWVd4Cmgv2VjN7SDIFw9xc0CopIrGkf6WCsNxO6EsVessqraqALiIdy1yhc2iiNIxw9WqkBkEd9Yj8TMjjAJUYEm5qNG2iv//4759kG4mkfjCD43xsjNNrogw/UhvfJHr8M3tCV/bVnisZ7L5ZYr+5McDILxIRcb+SPPeXjyt+bSs8Q/EJLsPfJBamWMtNCg9BrOOhJezgurYl7hXlLu/Q10skK1fXB9h2sqCdT49LXp81WkWZmtkaom1DmwXQluG3I9fHFd+nJ6ad4CFwaXMYq1zQf+HkKS9v01V24Q4PvAgMv4WlvAkVwkdoeoTKeJDyjiigNgXL/GUpZW457QoPXdBL/HawkCrQqWLSBwgo98GvmJBcl10HmyjHsi4Y5OT87fvz0++ZF+e/v28OSVELp0vxglJEur0aIobqJhc+soySs3YVyKcdMQ7i8Lq/TXcQYfNxW3jISwWw8Tnhx0U78J5elrdjOuIvzYsdb9wzDbHo2izyWL26LEBvR9GOjtuN4mhnWSysYnugF/n6FBAevDx771UNDzRTQAt5zj4MBJ6AADwUZxdmObYvn2BrVnh6aWsGnWaLZO6qqpqxBj+DAXiUekhQvkgZMuVX5M7qg5KxMUnO3fCxb3bVNO7+gtdCkADAi6Jpwvmfr4egKLIGKg2LzPgTu9R6ZMyBjRRkkvQr/WuGy11tI+7ZbgW8EEDuxM7j0zuTRvPnCoL2g5NiTejQzFhk+4cY2n8Ndw4+5tz/+3DmBnEdpC7AB9UmjKsrnkF8mTaOjv5DWvcAOzA30zZomzYcsM/n33FJN81h3FIOUaNNTw6Go9Ak2ZPJTZFR+EHG4YpT43spmD8LnYNsTQeaNdaDu1b/3xu7gd+903hj62ur9zLk73Sr7jj05UY5ez07m4ry322LPWRog7e6uavt8TqI819AB39rfuMO71dvcM+heCphuB0939Y/QE7gsYatQimTp+NJkgejGZDMK80VbZ5rYXJ7EAjbFbfzGgwBXiUsN93oeVGhT3og0b6GadtK5lwzHeAV28FpEtyHtyjEy6Zd21vbm8CdBAp0MiIRp/uVsmhxVEYxBrgEL78Gz/8n68tA1CwkiLOWLvB/E95+1WREoCmw8jOxHCnUv9F+hDBcZf7d20IC/vGPqkrNfVlhx49s3Th6PwHZbwjScl5y3c0P/KDaRDRbOIHZT/hVH77UBCEKVvF+Uh4V6/GA++KSzEVLelhLbJIfscFeINiLYn5r7ZbHbZpi8b0SLLaL8HUdDXHfpon85uUzwM2yIET7HAHdIKbokIqmCsaC8PzOuycCraOj1mDLTfAhX0LbfJbb+l6ejLXf5MQNky/g/fXiwMC4TBPTj1cMjYQ9+XCP6RanWpR7Gd4DeYwBXCDAzNd70RB0IMJZ9DZEOEa2OkzbPYLKUUwjXFUKFhGx7EILyoHhh/LAu3LUK5Q5rlXcnaefFeEct09SHi0RyzlNa48fS759oFrwOorbBM3CzLlOi7CmGzYx8jayjVnmm9Wrs+TzrYFZfciGJ1ebd1mknyVYhmCdvex67/lAxpmn4gtyoNLlGc4sKyFVIKM/D08gWiQFVR+sIksjoS1Dv4Fn58J7/tiiQVggr0JkN1TZA1h+ZAuF8piBSwqBlJgC5qJqey7VLU9gdE7p5LYuo885tDA0rfemjeNozs4/+8JmNOziYkMW4/GMt/ff0kLSuHpv04efX6zWDXhhCLI+NrGVKf7wq4v1W333S29PUAUlLY3GSAmun7vpwD3zGS3FK+UY0H0gRhtAGZ3Wnfk7J7LT9Gv2W5wI+WxJxsU4bUFpSSRy62gJIqzSu0ng5aXnLjDHRZgrbpc+9tRrzk4/LRfJldL7S36YCmvsnQWXkTEYpQLFZIydclJL4BeIAivWehBehN+0hUosc7nIL7o8mPgg5SnJnkWN7SziEO3QL9qnd25W1alS64n5lEsF9It92NCbKqiYzKRh7LcaDitSkF0K6y0iu0ExXpTNtv6wzDdgHcOcVX2HIPB+8APnbKoEF/126+M1mSsB7E/0RPqZ0yTbb2TzSe6n2W0xpWHfRUemW41oJrJHpFwyW3E67ROQi6RmhLkPAr2TsajrQL6fau8q3Egu6BIfdKB70tS0qms8nN9tiDA20ov79pb0PtBG1jmoZAm61jupPonpqmKfcvwS43FjE+O/uyRXCR0P+PRaBn+EYWpz25LWg78y7F9LfuBQkfj7j3gkNgxrc9OPxxc3gPHeWJ/FNuusC5Og2I0GQIWErPimQHRL7aTspjassncl38SV4vl4N9A8OvMW7QpGWjEdkWsJCqoZZobjEe8R0Zj08Hg40qFxqhVywkjvV0Vx6qc6/j4m698zrHbq7qnqg3zeT0u913NtuQ+LYMYS+ioGdU/55mPGjivtlehSNgTTvNuTbhudLmLG33qNi8zcRO2ugQhb95It2OwjWTAbPTfuGSQLJDmjbbauMOpYqDSfXZ3l++VpD9Z98EInM7R/lvS8fPpD83HN0vBufNu+fP7glcdEA/nCEPi2GVm0NM898JkMxOVTYNEJqCbP3jGAlXIWo1n/61A2hM6eHkMyZBkTD/zRa5D0Kf10tb2baCre+rqXF1e8iGJWnQ34rpUFpDBWd2nyHdbROmUyAPtzv8E3xoGEmDbhPWyDN01km1u85EW2b5djr6Nz34WyQwwz83Y9KarekwVeYWdQUe4s75O1uvKeCg2842Dw047KJ8J5KQV2AWmTa1IHtwFHbWYivRW+8w++T+KPHMmhZJAsBEY6YVtin0PjwZZnEcm42uXpEBNdigrhdnfu07pkqksrHzxH1I1cpFxznp2cUpN+xALrwSseDPCbzmXXAkQ9FCG/Hd0tTC8g6KbVs8rgv0j8fe5xxbf5LajyzOm3bkinZFk/wBH7G3Yo/wc6u9Y5EVICz43nVqnupJp8XMxYMmyeIj3Lnp2AGtOh481PhTguGbXdju7ab2cI+k+xWvIx91vYd4AlJp+J/wA/Rw9Ox08svZ6cmbvw2GzYK2Gld+Jt493NCRg3uKJ3o9+FHcKWQy4avEkwnoZTLRG8Wd9atKE4L6Qu8XOs37cHJueVKirpvIhgjASwUlUlbIcF1BOht/0QBukNwE0qtG3tlgz8aZxn30EU6+LJM4cXdnSQ2PaWulsRlDESVC8k2kL1CbidQujBrvl/9CkNSXBX/5BlEHuazXcKNkvGhHFbHzs3gTj36uB6Raz/fvAmP28d6g9z+6Yx2u7mwAAA=="
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
