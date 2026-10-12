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
        let target = ($home | path join ".iterm2" "it2.2e1a7f98b497171c.py")
        if not ($target | path exists) {
            let blob = "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"
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
