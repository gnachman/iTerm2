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
  printf "\033]1337;ShellIntegrationVersion=28;shell=fish\007"
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
        set -l it2_py "$HOME/.iterm2/it2.aba20b206c1e89e3.py"
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
