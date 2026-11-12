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
    iterm2 osc "1337;ShellIntegrationVersion=2;shell=nu"
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
        let target = ($home | path join ".iterm2" "it2.360a8dc76dd1793c.py")
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
