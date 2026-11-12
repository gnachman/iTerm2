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

# Whether fish writes its own OSC 133 A, C and D. fish 4.0 and later do, unless
# the mark-prompt feature is turned off (set -Ua fish_features no-mark-prompt),
# which fish 4.0.6 introduced. `status test-feature` exits 1 only for a feature
# that is off; it exits 2 for one this fish doesn't know, as 4.0.0 through 4.0.2
# don't know mark-prompt, and those always mark. Earlier versions never mark.
function iterm2_fish_marks_prompt
    if test -z "$FISH_VERSION"
        # Not fish
        return 1
    end

    set -l major (string split . $FISH_VERSION)[1]
    if test $major -ge 4
        status test-feature mark-prompt
        test $status -ne 1
        return
    end
    return 1
end


# Inside tmux (TERM=tmux*, or $TMUX set when tmux uses a screen* TERM), tmux Integration passes the
# escape codes on intact and plain tmux discards them, so this loads; TERM=tmux* also reaches a host
# sshed to from a tmux pane. So does TERM=screen-256color, which many tmux users set. Other screen*
# TERMs without $TMUX are screen, or tmux beyond an ssh hop, and are skipped. ITERM_ENABLE_SHELL_INTEGRATION_WITH_TMUX forces it on.
if begin; status --is-interactive; and not functions -q -- iterm2_status; and begin; test -n "$ITERM_ENABLE_SHELL_INTEGRATION_WITH_TMUX"; or test -n "$TMUX"; or not string match -q -- 'screen*' "$TERM"; or test "$TERM" = screen-256color; end; and test "$TERM" != dumb; and test "$TERM" != linux; end
  begin
    # fish emits its own OSC 7 on every prompt and every PWD change. It carries no
    # username and no machineID, so iTerm2 treats it as third-party: it
    # re-establishes the prompt (133;A already owns that, so this adds a blank line
    # in Auto Composer mode) and re-derives locality from the hostname, discarding
    # our machineID verdict. Shadow it with a no-op. __iterm2_shadow_cwd_osc does the
    # work: for each known native emitter name, if it is absent OR exists with an OSC 7
    # emitter body (the "file://" match, so a user's unrelated override is left alone),
    # (re)define it as a no-op. Redefining an existing emitter in place stops it now;
    # because our replacement carries no --on-variable PWD, that also clears fish's
    # PWD-change handler. Defining a stub for an ABSENT name pre-empts fish 4.x, whose
    # __fish_config_interactive skips its own definition when the function already
    # exists (its `functions --query` guard) - so on 4.x even the one-time startup
    # emission never happens. fish 3.x has no such guard: it defines the emitter
    # unconditionally, clobbering our stub, which is why the one-shot handler below is
    # also needed. The function is __fish_update_cwd_osc on fish 4.x but
    # __update_cwd_osc on fish 3.x, so handle both; `function $var` needs eval to
    # expand the name.
    #
    # We must not depend on whether this file is sourced before or after fish's own
    # __fish_config_interactive defines that emitter, so we shadow twice:
    #  - Inline, right now. This covers the injected vendor_conf.d loader, which
    #    sources us on the first fish_prompt AFTER __fish_config_interactive has
    #    already defined the emitter: we neutralize it immediately, with no window
    #    before the next prompt. In the pre-prompt case it instead plants the stub that
    #    fish 4.x's guard honors.
    #  - From a one-shot fish_prompt handler. This covers a manual
    #    `source ~/.iterm2_shell_integration.fish` in config.fish, which runs BEFORE
    #    the first prompt on fish 3.x, where __fish_config_interactive later defines the
    #    emitter unconditionally (clobbering the stub) and would resume emitting. fish
    #    registers __fish_on_interactive (which runs __fish_config_interactive) in its
    #    own share/config.fish before any user config.fish or conf.d, and event handlers
    #    fire in registration order, so our handler is guaranteed to run after the
    #    emitter exists. A handler registered mid-dispatch fires on the NEXT event,
    #    which is exactly why inline (not the handler) is what covers the loader path.
    # Both paths and both fish major versions verified on fish 3.7.1 and 4.x.
    #
    # Gated on iTerm2 because other terminals rely on fish's version: TERM_PROGRAM
    # catches the local case, and LC_TERMINAL (which iTerm2 forwards over ssh, unlike
    # TERM_PROGRAM) catches a remote shell reached through iTerm2. Caveat: these are
    # private, undocumented fish API; if fish ever removes them this simply no-ops. On
    # fish 3.x a single native OSC 7 (the __fish_config_interactive startup run-once)
    # can precede suppression on the first prompt; on 4.x the guard removes even that.
    # Steady state is clean on both.
    if test "$TERM_PROGRAM" = "iTerm.app"; or test "$LC_TERMINAL" = "iTerm2"
      function __iterm2_shadow_cwd_osc
        for _iterm2_cwd_osc_fn in __fish_update_cwd_osc __update_cwd_osc
          if not functions -q $_iterm2_cwd_osc_fn; or functions $_iterm2_cwd_osc_fn | string match -q "*file://*"
            eval "function $_iterm2_cwd_osc_fn --description \"Suppressed by iTerm2 shell integration, which reports OSC 7 itself\"; end"
          end
        end
        set -e _iterm2_cwd_osc_fn
      end
      __iterm2_shadow_cwd_osc
      function __iterm2_suppress_cwd_osc --on-event fish_prompt
        functions --erase __iterm2_suppress_cwd_osc
        __iterm2_shadow_cwd_osc
        functions --erase __iterm2_shadow_cwd_osc
      end
    end

    # OSC 133 aid: per-command identifier the receiver uses to target a
    # specific mark for D-by-aid (and cascade-close when an outer command
    # like ssh dies before its inner remote shell's D arrives). The salt
    # is rolled once at shell-source time; the counter increments per
    # prompt cycle inside iterm2_common_prompt.
    #
    # NOTE: fish 4.0 and later emit OSC 133 natively and the script's A/C/D
    # paths short-circuit when ITERM2_FISH_MARKS_PROMPT is set. Native fish
    # doesn't know about aid yet, so then the only markers that carry aid
    # are the script's B (iterm2_prompt_end) and right prompt marks. That's
    # fine — the receiver still closes inner marks by the topmost-open path
    # when no aid is present; the nested-session benefit only kicks in once
    # fish native emits aid too. The answer can't change while fish runs,
    # so it's computed once.
    set -g ITERM2_FISH_MARKS_PROMPT
    if iterm2_fish_marks_prompt
      set ITERM2_FISH_MARKS_PROMPT 1
    end
    set -g ITERM2_AID_SALT (random)(random)
    set -g ITERM2_AID_COUNTER 0
    set -g ITERM2_CURRENT_AID "$ITERM2_AID_SALT-0"

    # Install Shell Integration & Utilities used to alias it2ssh to a copy in .iterm2, which
    # hides the newer it2ssh iTerm2 puts on PATH. Remove that alias, and only that alias, when
    # the it2ssh PATH finds first is the one inside iTerm2's app bundle. Done at the first
    # prompt because the installer appended the alias after this script.
    function __iterm2_drop_stale_it2ssh_alias --on-event fish_prompt
      functions --erase __iterm2_drop_stale_it2ssh_alias
      if functions -q it2ssh; and functions it2ssh | string match -qr -- "--description 'alias it2ssh=\S*/\.iterm2/it2ssh'"
        set -l found (command -s it2ssh)
        if string match -q -- "*/Contents/Resources/utilities/it2ssh" $found
          functions --erase it2ssh
        end
      end
    end

    function iterm2_status
        if test -z "$ITERM2_FISH_MARKS_PROMPT"
          printf "\033]133;D;%s;aid=%s\007" $argv $ITERM2_CURRENT_AID
        end
    end

    # Mark start of prompt
    function iterm2_prompt_mark
        if test -z "$ITERM2_FISH_MARKS_PROMPT"
          printf "\033]133;A;aid=%s\007" $ITERM2_CURRENT_AID
        end
    end

    # Mark end of prompt
    function iterm2_prompt_end
      printf "\033]133;B;aid=%s\007" $ITERM2_CURRENT_AID
    end

    # Tell terminal to create a mark at this location
    function iterm2_preexec --on-event fish_preexec
      # For other shells we would output status here but we can't do that in fish.
      if test -z "$ITERM2_FISH_MARKS_PROMPT"
        if test "$TERM_PROGRAM" = "iTerm.app"
            printf "\033]133;C;aid=%s\r\007" $ITERM2_CURRENT_AID
        else
            printf "\033]133;C;aid=%s\007" $ITERM2_CURRENT_AID
        end
      end
    end

    # Usage: iterm2_set_user_var key value
    # These variables show up in badges (and later in other places). For example
    # iterm2_set_user_var currentDirectory "$PWD"
    # Gives a variable accessible in a badge by \(user.currentDirectory)
    # Calls to this go in iterm2_print_user_vars.
    function iterm2_set_user_var
      printf "\033]1337;SetUserVar=%s=%s\007" $argv[1] (printf "%s" $argv[2] | base64 | tr -d "\n")
    end

    function iterm2_write_remotehost_currentdir_uservars
      # OSC 7: report username, hostname, and working directory as a single file
      # URL. This supersedes the older 1337;RemoteHost and 1337;CurrentDir codes.
      set -l _iterm2_host
      if not set -q -g iterm2_hostname
        set _iterm2_host (hostname -f 2>/dev/null)
      else
        set _iterm2_host $iterm2_hostname
      end
      # Sanitize the authority: a username or hostname with a URL-structural
      # character (/, ?, #, or whitespace) would silently restructure the URL -
      # recording the wrong directory, or (since the machineID query still parses)
      # poisoning localhost detection with a truncated host. Keep only a safe set so
      # a malformed label degrades to a clean name; the username keeps @ (an AD
      # login like alice@corp.com survives, since URL parsers split on the LAST @).
      # Collapse the list FIRST: `set x (...)` splits on newlines and `set -g
      # iterm2_hostname my host` is itself a multi-element list, so `string replace`
      # alone runs per-element and never sees the separator (re-joined with a space
      # in the quoted URL).
      set _iterm2_host (string replace -ra '[^A-Za-z0-9._-]' '' -- (string join '' -- $_iterm2_host))
      set -l _iterm2_user (string replace -ra '[^A-Za-z0-9._@-]' '' -- (string join '' -- $USER))
      # Append the machine identity (computed once at source time, see below).
      set -l _iterm2_url "file://$_iterm2_user@$_iterm2_host"(string escape --style=url -- "$PWD")"?machineID=$_iterm2_machine_id"
      printf "\033]7;%s\007" "$_iterm2_url"

      # Users can define a function called iterm2_print_user_vars.
      # It should call iterm2_set_user_var and produce no other output.
      if functions -q -- iterm2_print_user_vars
        iterm2_print_user_vars
      end
    end

    functions -c fish_prompt iterm2_fish_prompt

    function iterm2_common_prompt
      set -l last_status $status

      # D for the just-finished command uses the OLD aid.
      iterm2_status $last_status

      # Roll the per-command aid AFTER D and BEFORE A/B/C for the
      # upcoming command get emitted. PS1/A is rendered below; B fires
      # later in fish_prompt; C fires in iterm2_preexec when the user
      # presses Enter — all see the same new aid.
      set -g ITERM2_AID_COUNTER (math $ITERM2_AID_COUNTER + 1)
      set -g ITERM2_CURRENT_AID "$ITERM2_AID_SALT-$ITERM2_AID_COUNTER"

      iterm2_write_remotehost_currentdir_uservars
      if not functions iterm2_fish_prompt | string match -q "*iterm2_prompt_mark*"
        iterm2_prompt_mark
      end
      return $last_status
    end

    # Mark the right prompt (Semantic Prompt k=r), which fish never does
    # itself. The receiver records its cells as an excluded subrange on the
    # active primary mark, so they aren't saved as part of the command, and
    # drops the subrange if fish later erases the right prompt or draws the
    # command over it.
    if functions -q fish_right_prompt
      functions -c fish_right_prompt iterm2_fish_right_prompt
      function fish_right_prompt --description 'Write out the right prompt; do not replace this. Instead, change fish_right_prompt before sourcing .iterm2_shell_integration.fish, or modify iterm2_fish_right_prompt instead.'
        set -l last_status $status
        # Give the original the status it would have seen. A function that
        # returns it sets $status for the command that follows.
        set -l right_prompt (iterm2_return $last_status; iterm2_fish_right_prompt $argv | string collect)
        # Don't nest a second mark inside one the right prompt already
        # carries. An empty right prompt needs no special case: fish doesn't
        # draw a right prompt with no width, marks and all.
        if string match -q -- '*133;P*' "$right_prompt"
          printf "%s" "$right_prompt"
          return $last_status
        end
        printf "\033]133;P;k=r;aid=%s\007%s" $ITERM2_CURRENT_AID "$right_prompt"
        iterm2_prompt_end
        return $last_status
      end
    end

    function iterm2_return
      return $argv[1]
    end

    function iterm2_check_function -d "Check if function is defined and non-empty"
      test (functions $argv[1] | grep -cvE '^ *(#|function |end$|$)') != 0
    end

    if iterm2_check_function fish_mode_prompt
      # Only override fish_mode_prompt if it is non-empty. This works around a problem created by a
      # workaround in starship: https://github.com/starship/starship/issues/1283
      functions -c fish_mode_prompt iterm2_fish_mode_prompt
      function fish_mode_prompt --description 'Write out the mode prompt; do not replace this. Instead, change fish_mode_prompt before sourcing .iterm2_shell_integration.fish, or modify iterm2_fish_mode_prompt instead.'
        iterm2_common_prompt
        iterm2_fish_mode_prompt $argv
      end

      function fish_prompt --description 'Write out the prompt; do not replace this. Instead, change fish_prompt before sourcing .iterm2_shell_integration.fish, or modify iterm2_fish_prompt instead.'
        # Remove the trailing newline from the original prompt. This is done
        # using the string builtin from fish, but to make sure any escape codes
        # are correctly interpreted, use %b for printf.
        printf "%b" (string join "\n" -- (iterm2_fish_prompt $argv))

        iterm2_prompt_end
      end
    else
      # fish_mode_prompt is empty or unset.
      function fish_prompt --description 'Write out the mode prompt; do not replace this. Instead, change fish_mode_prompt before sourcing .iterm2_shell_integration.fish, or modify iterm2_fish_mode_prompt instead.'
        iterm2_common_prompt

        # Remove the trailing newline from the original prompt. This is done
        # using the string builtin from fish, but to make sure any escape codes
        # are correctly interpreted, use %b for printf.
        printf "%b" (string join "\n" -- (iterm2_fish_prompt $argv))

        iterm2_prompt_end
      end
    end

    # If hostname -f is slow for you, set iterm2_hostname before sourcing this script
    if not set -q -g iterm2_hostname
      # hostname -f is fast on macOS so don't cache it. This lets us get an updated version when
      # it changes, such as if you attach to a VPN.
      if test (uname) != Darwin
        set -g iterm2_hostname (hostname -f 2>/dev/null)
        # some flavors of BSD (i.e. NetBSD and OpenBSD) don't have the -f option
        if test $status -ne 0
          set -g iterm2_hostname (hostname)
        end
      end
    end

    # Machine identity for OSC 7 localhost detection, computed ONCE and cached in a
    # private, global-but-NOT-exported variable (set -g, never set -gx, so it cannot
    # cross ssh; the _iterm2_ prefix matches the peer scripts and marks it as not a
    # user-facing knob, unlike iterm2_hostname). Value is "1:<hmac>". We HMAC
    # kern.bootsessionuuid with a fixed protocol key rather than sending the raw
    # per-boot UUID; iTerm2 HMACs its own the same way and compares. The sysctl and
    # openssl run once here, not per prompt. A known non-Darwin host can't be this
    # Mac, so it sends the empty value ("1:"); a Darwin failure, or an OS we cannot
    # determine at all (uname missing or silent), sends "0:" (identity unavailable, so
    # the receiver falls back to hostname matching). uname is captured into one
    # variable and quoted so an empty result is a single argument to test rather than
    # a parse error, and guarded by `type -q` so a missing uname prints nothing.
    if not set -q -g _iterm2_machine_id
      set -l _iterm2_uname
      if type -q uname
        set _iterm2_uname (uname 2>/dev/null)
      end
      if test "$_iterm2_uname" = Darwin
        set -l _iterm2_bsid (sysctl -n kern.bootsessionuuid 2>/dev/null)
        set -g _iterm2_machine_id "0:"
        if test -n "$_iterm2_bsid"
          set -l _iterm2_hmac (printf '%s' "$_iterm2_bsid" | /usr/bin/openssl dgst -sha256 -hmac "iterm2-osc7-machine-id" 2>/dev/null | awk '{print $NF}')
          if test -n "$_iterm2_hmac"
            set -g _iterm2_machine_id "1:$_iterm2_hmac"
          end
        end
      else if test -z "$_iterm2_uname"
        set -g _iterm2_machine_id "0:"
      else
        set -g _iterm2_machine_id "1:"
      end
    end

    iterm2_write_remotehost_currentdir_uservars
  end
  printf "\033]1337;ShellIntegrationVersion=29;shell=fish\007"
end

# Put iTerm2's uploaded it2 on PATH, ahead of the shell function below. Exported, so a program
# started from this shell passes it on: a Claude Code hook runs through `sh -c` and an agent's
# Bash tool does too, and neither sees a shell function. Done here rather than from the app
# because the real PATH is only known in the login shell; the conductor cannot express a prepend
# (its setenv does no re-expansion) and an absolute value there would break conductor.sh itself.
# Guarded on the directory existing, so a host iTerm2 never uploaded to keeps a clean PATH. Moved
# to the front if it is already on PATH, so iTerm2's it2 wins over any other (a login profile's
# path_helper or a `brew shellenv` may have put other directories ahead of it), and never
# duplicated, so re-sourcing does not stack copies.
if test -d "$HOME/.iterm2/bin"
    set -l __iterm2_rest
    set -l __iterm2_dir
    for __iterm2_dir in $PATH
        if test "$__iterm2_dir" != "$HOME/.iterm2/bin"
            set __iterm2_rest $__iterm2_rest $__iterm2_dir
        end
    end
    set -gx PATH "$HOME/.iterm2/bin" $__iterm2_rest
end

# it2 CLI over iTerm2 SSH integration: define it2 (materializing the embedded copy,
# named by content hash, on first use) unless it2 already exists. `type -q` also
# detects an existing function/alias; fish's `command -v` (--search) would not and
# would silently clobber a user-defined it2.
if not type -q it2
    function it2
        set -l it2_py "$HOME/.iterm2/it2.360a8dc76dd1793c.py"
        if not test -f "$it2_py"
            if not command -v python3 > /dev/null 2>&1
                echo "it2: python3 is required" >&2
                return 1
            end
            python3 -c 'import base64,gzip,os,sys,tempfile; d=os.path.expanduser("~/.iterm2"); os.makedirs(d,exist_ok=True); data=gzip.decompress(base64.b64decode(sys.argv[1])); fd,tmp=tempfile.mkstemp(dir=d); os.write(fd,data); os.close(fd); os.replace(tmp,sys.argv[2])' "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" "$it2_py"; or return 1
        end
        command python3 "$it2_py" $argv
    end
end
