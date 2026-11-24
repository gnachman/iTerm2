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
        let target = ($home | path join ".iterm2" "it2.4f5d263fc6b8b1a2.py")
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
