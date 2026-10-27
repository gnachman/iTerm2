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
# forwarded over SSH. Inside tmux (TERM=tmux*, or $TMUX set when tmux
# uses a screen* TERM), tmux Integration passes the escape codes on
# intact and plain tmux discards them, so this loads, as the other
# shells' integration does; TERM=tmux* also reaches a host sshed to from
# a tmux pane. So does TERM=screen-256color, which many tmux users set.
# Other screen* TERMs without $TMUX are screen, or tmux beyond an ssh
# hop, and are skipped. ITERM_ENABLE_SHELL_INTEGRATION_WITH_TMUX forces
# it on. In tmux, TERM_PROGRAM is tmux's own.
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
let iterm2_in_tmux = (($env.TMUX? | default "") != "")
let iterm2_active = (
    $nu.is-interactive
    and ($env.ITERM_SHELL_INTEGRATION_INSTALLED? | default "") == ""
    and (not (iterm2 hook-registered))
    and (
        $iterm2_term_program == ""
        or $iterm2_term_program == "iTerm.app"
        or ($env.LC_TERMINAL? | default "") == "iTerm2"
        or ($iterm2_term_program == "tmux" and ($iterm2_in_tmux or ($iterm2_term | str starts-with "tmux")))
    )
    and $iterm2_term not-in ["linux", "dumb"]
    and (
        ($env.ITERM_ENABLE_SHELL_INTEGRATION_WITH_TMUX? | default "") != ""
        or $iterm2_in_tmux
        or not ($iterm2_term | str starts-with "screen")
        or $iterm2_term == "screen-256color"
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

# Put iTerm2's uploaded it2 first on PATH, as the other shells' integration
# does, so a program started from this shell (a Claude Code hook through
# `sh -c`, an agent's Bash tool) finds iTerm2's it2 rather than another
# one. Only when the directory exists, so a host iTerm2 never uploaded to
# keeps a clean PATH; moved to the front if it is already there, and never
# duplicated. PATH is a list once nushell has started, but may still be a
# string this early.
let iterm2_home = ($env.HOME? | default "")
let iterm2_bin = ($iterm2_home | path join ".iterm2" "bin")
if $iterm2_home != "" and ($iterm2_bin | path exists) {
    let iterm2_current = ($env.PATH? | default [])
    let iterm2_path = if (($iterm2_current | describe) | str starts-with "list") {
        $iterm2_current
    } else {
        $iterm2_current | split row (char esep)
    }
    # $it rather than a closure, which `where` takes only from 0.105 on.
    $env.PATH = ([$iterm2_bin] | append ($iterm2_path | where $it != $iterm2_bin))
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
        let target = ($home | path join ".iterm2" "it2.aba20b206c1e89e3.py")
        if not ($target | path exists) {
            let blob = "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"
            let materialize = (do --ignore-errors {
                ^$py -c 'import base64,gzip,os,sys,tempfile; d=os.path.expanduser("~/.iterm2"); os.makedirs(d,exist_ok=True); data=gzip.decompress(base64.b64decode(sys.argv[1])); fd,tmp=tempfile.mkstemp(dir=d); os.write(fd,data); os.close(fd); os.replace(tmp,sys.argv[2])' $blob $target | complete
            })
            if ($materialize | is-empty) or $materialize.exit_code != 0 {
                error make --unspanned {msg: "it2: could not be installed"}
            }
        }
        ^$py $target ...$args
    }
}
