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

function is_fish_4_1_or_later
    if test -z "$FISH_VERSION"
        # Not fish
        return 1
    end

    set -l parts (string split . $FISH_VERSION)
    set -l major $parts[1]
    set -l minor $parts[2]

    if test $major -gt 4
        return 0
    else if test $major -eq 4 -a $minor -ge 1
        return 0
    else
        return 1
    end
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
    # NOTE: fish 4.1+ emits OSC 133 natively and the script's A/C/D
    # paths short-circuit via is_fish_4_1_or_later. Native fish doesn't
    # know about aid yet, so on fish 4.1+ the only marker that carries
    # aid is B (iterm2_prompt_end). That's fine — the receiver still
    # closes inner marks by the topmost-open path when no aid is present;
    # the nested-session benefit only kicks in once fish native emits
    # aid too.
    set -g ITERM2_AID_SALT (random)(random)
    set -g ITERM2_AID_COUNTER 0
    set -g ITERM2_CURRENT_AID "$ITERM2_AID_SALT-0"

    function iterm2_status
        if not is_fish_4_1_or_later
          printf "\033]133;D;%s;aid=%s\007" $argv $ITERM2_CURRENT_AID
        end
    end

    # Mark start of prompt
    function iterm2_prompt_mark
        if not is_fish_4_1_or_later
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
      if not is_fish_4_1_or_later
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
  printf "\033]1337;ShellIntegrationVersion=26;shell=fish\007"
end

# Put iTerm2's uploaded it2 on PATH, ahead of the shell function below. Exported, so a program
# started from this shell passes it on: a Claude Code hook runs through `sh -c` and an agent's
# Bash tool does too, and neither sees a shell function. Done here rather than from the app
# because the real PATH is only known in the login shell; the conductor cannot express a prepend
# (its setenv does no re-expansion) and an absolute value there would break conductor.sh itself.
# Guarded on the directory existing, so a host iTerm2 never uploaded to keeps a clean PATH, and
# on absence from PATH, so re-sourcing does not stack duplicates.
if test -d "$HOME/.iterm2/bin"; and not contains "$HOME/.iterm2/bin" $PATH
    set -gx PATH "$HOME/.iterm2/bin" $PATH
end

# it2 CLI over iTerm2 SSH integration: define it2 (materializing the embedded copy,
# named by content hash, on first use) unless it2 already exists. `type -q` also
# detects an existing function/alias; fish's `command -v` (--search) would not and
# would silently clobber a user-defined it2.
if not type -q it2
    function it2
        set -l it2_py "$HOME/.iterm2/it2.9ec2bce60a6b86bf.py"
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
