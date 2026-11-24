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
        set -l it2_py "$HOME/.iterm2/it2.4f5d263fc6b8b1a2.py"
        if not test -f "$it2_py"
            if not command -v python3 > /dev/null 2>&1
                echo "it2: python3 is required" >&2
                return 1
            end
            python3 -c 'import base64,gzip,os,sys,tempfile; d=os.path.expanduser("~/.iterm2"); os.makedirs(d,exist_ok=True); data=gzip.decompress(base64.b64decode(sys.argv[1])); fd,tmp=tempfile.mkstemp(dir=d); os.write(fd,data); os.close(fd); os.replace(tmp,sys.argv[2])' "H4sIAAAAAAACA7V9a3fbRpL2d/6KXnjyCpyQ0MVOdlYOfVaRaUcbW/KR5FzWo0OBBEghAgEOLpY1efPft56qaqBBUrJnZtcfZAJo9KW67lVdePJvu3VZ7E6TbDfOPprVfXWTZ097nuedx8u8is11Uh1cm1maxFll5nlhksu4WB6Yi4sfTJJV8aIIqyTPgl7v55s4M/d5bcIiNmV5sxOhQW5Cc5OXlfmYhPruTrn+9sBUN7GZ5VlUz6q82Cl78yJcxkWwujfxp1VeVCV1U2fJJxPlyzDJTJnPbuPK+KuwuqGezJ9OLg8mF2fHP/apq7AyqyL/lMSlofGp616az8JUhw/M5U1CT5Ls3pRVlCbTYZ6l93aNv9UlL/QuLCIatVh8NF+bil5MMuqC5ljFn6qe9Guk32U4u0myeGDubmJaOx78uYjD9M+GgEevLJdhFpmqiGPjx8tpHEUxYKPz6ZuizsoemkRJSQua3TQTN0fvTkwZFx/j4jkmm9fVLv0XF8Vu/Cmp6BaNszTTcHaLZcV2EVlMb/SmdZJiDRl3U8R/q2NaW1KVcTofEAgN9xDe02hFQvuTEhQA2/tsZu4SAixmcHGXzPHSAbY4oeURaKt8lqfGrwBHHfG74Qsjm6Z70x+YNM4W1c1wVcTz5BMtmZ+Xh72eoX8f9s30nhCsul/FVx+eycU0WQzjLEpoyqvwPs3DSDu5+qDXV73e+5Uu29exaWgF5SF3vfPDjvlh/ObNGf3+rcyzQ/O7nfTAZHk2o63Cxg7M7C4a8OYOTFKGVXVPt/K0HJgiv6O/RBIDgD3J/pCOj3fM8dHp8fiNMfFyVd0b41+cvD45vXxu6pJWOL0nlMgWQ9rRLMkWu8s8SwihLQ6U/V7vZX6X2fkrLdH8ZSV2/mc75uLy5dn7S2OK8I5BU8qTMT8Zn59vPPllx4x/Obk07ZpneRT/QZd+GgKlAfznQOAsnoHosLsZDZyXMeZ1TuhB21saJgbs/DtmBsCQLCJiMEQpRVjcG2CqPnsa/PvXxl/UYRESXRAAaK9LWshhDx0oPjCaVGF6y1gdprT26J6RnkiacJmQqx+A5fR6yRLETvhcxt8+s1dYjv2dl/ZXeVNXSdpcJQsiz+aKMbC5qgpiK81VPSVkmMVl29N987NKlnGvJ7gzMlPvB6/3xFwAxxKGl6BVYJkgU2YpCySCKwFVQCdPaVkD/km4T5gB9pXFd7RWRVkmrzCj3om/pWHGbJAGKSsCjsnnRjEIJHoTpnOBVFnleRSY7+vlih4Q5uaLmGZVtNQarlbEPZ+YY8tLiS++jJf1p8BSwE8yT2ZWzprMgthqSZBbUo8YOGwY1yzMsrzCjKjjWV4UhD+EIhiT+FFgjrQHnkSWG88O5QEdorBiEBE6JHEaMVBmeZ2BpZcCqaD37vzs8uz47M3kp/H5xcnZKQF/v6eUhn049npKECOTF5HvnXn9nhKC3hnTHSYAvf6Frmm+RyaKZymJJGU/yk9MOM0/xrJzwE7CyYqahNgoYepoDThEMfNDPzS0klDY1DIpgcTUvbwgXQqf6/MKqfuCOiRGEvIGkVAiYBf36JGIYFrP57ibQ8owcJ6Z18n3pn56QNLkU7KslwH1/jrO4iKviRNN41lIeMSDLRJCU5ouycK7bCirmoVFkTDxxoY2ZVVXRK4ikpLZDbaQujAEhwVkULBA7xDthMIloy3Wcw3EC4HJwsa4i/5znp+y3yHaMZnQKNRlmt8x/KgFJB6YRZpS32AJYK2AL0vURQJKoWkky2VMDL6iuc3SOCwMCTPikFAt6Gk+/ZjQggm9pvmiLhW0Qe/t0S+TV+dHb8eTN+PT15c/0C4ffPOt+bPZ3zt4pv/RsGfE26Fw0CQJvLrz2KKuNBlACArzJD6S10BLgt9HFm7E19P7wJzM7aqwz7yukjY+GtqugBGMGwMjc68zGmuVZyV3FMcFiUBAChvCSFHWxTzEBDNdtNI79U+AnxLe3QI/CBQQ3wbMhMaffRSV5t34nXn279+Y2zhelXRfscmXHQ5TkuflHc2SJJeSG/ELsIKqSIfHfVV7opjYeExYGROMo5wAcHp2CbYBpi86RxKlsbkLE9H3cCcjlUfIh3Q3Be5waELq3RV35trKu+FwnmMm1w66QrmgngnucXUXE+8RdYCI/+jXN2dHLyfnY/pzefJ2LHT+dA/0e1nUMZA4Fb2Klb/qhrEQpEvAjkjbJJ1hwt0FrKmQ2kiKFMlZsCNpXbLCgy4g36jjVU6IP02xw6RyEDAtHotAJ66b0WwLgBFLY3lJLUpQm05AphUqY0mwMmoKbKEOA3plQmKJ1FxDGt3sVuXEPA0XKhmquqApEg2Am4IbE8gxRFxZ7Yz1OJ0h8W3pWpeKHZC9p3fubu6xVqAQLjOSxXF0yOvBG0b0ZBXu3GmV1zQtVlmIaVDPsiiRWoxwusq1OdC0gt4EnQIsI/OKMI9kZi+K587kfIjggZlDuxtY6htNPU9VnEWaT4ld2H74XjKnGYIkQqJiX9+B/lXoS/hnqW9kfwVxBkXH9+pqPvwLMX20UhwdyQRIgRcdIFiRoux7L048Vk7tGH15CZK+EtLBHk1jEGILQkUf0TQa9ABnFQjlU1YHjAdhqevytGPBlLuYbSNVJYiXgNCI8u8KIhEWuYLD/JIDYtAA3yMsbSEBCAdoRDTv64K/tlCRFc1hs6TOOw/sG5jMJP4UzirdN1IPIuoR/H90SuihG/AEXPHaPrkGCwSDC4jsSeJnyczv8w3awuWqD3wD21fz7ucfzt6MmZ+aJdtYSZaUN8A/KKJ2gJhsKWF6pNpYwQKqx6yndUR3IXTBv1UKMa2EpoQoIjtmdpvGVmUBqzTQSKvKItkTCIO4GPIQzOnQTRGYn0WdMWGzctluViWJ7c1qUnyyqpF9YJmQuD6brgRmoo0dHUJ3g9dKMg6Sj4iZFN6YjRXL6a10TjDcYo0vMg2XfUGG2U2dEQMZmQ9XfN2CZGQyviMY1t5/YfbabSfKahYF7kCgwa62DfBPgTtqmw43drfzAvWq73w3ckez/4owKS0AAwWb71kCZuA0Q8WfZsyyvO4QiuOVfVvGa9swXGjK3A5b6jcQ6Lurx4q5bXeWwoIZFt0uy4C2l0jF56u2qxa+wxFzEOe5dkY8LvgtT/QRLKuWxFrW2BAUjHYXXW5CEVqKZSR2VnVBsio+fABNeD+LJTRWqCHarViYaG61eH9dNvct4UC1iSMW8qpNsvBnIgXgWJcNunx1g2N807c8XNvQvLo45gB70IJcGPRI3/qwJ/itGvXI8u06czi3Nt0//Oaqb1+gcfWdF2ZdV2ynEK9IlhMOko5w2Cj4oor5282EryJFzdLq5aQPM0Do1eCvmWe+0qb9zyxUsVAab0BFBSUhj4MXjQisszS5jRtVzNmlwQP663PSn+ssWme8MNEaNkiydkE8w9IgDLlNzggkvOMRprGwUnDsmG0ExnCH/Q6V/eoI1nIqCTlTi65qOoGHW07AevhAOD8vA7vyXctnw6Lq6xzEr6Uorto0qUFYZcNKeOEiOaqccNs0Jgv9WpBZQjpoCbErzIMQC1vJnTZ9jDbl2tdmm566KZZbBWWDRqzx0YhW+0NwB4i2qozf5ZgDcyk/xsDTgTm74B/9L8NqS9yAgagYX0VDtmEFh6y68FmkbpfVku66dtGBwzb2zapEO29Zry6o++YqLEtLNnboL+QoXYrSl5ULWz8uKeZ/j/2GCZf3ZSDeVTuI6OPtPXaTRVYnjD/FMzGjxYie57l58f+G18xSN/oM5iSas5xwiCViaY4qIpRpXcW8cNCdOgR1lCQbqotK39AufwrTOlY0YDcTuxb03XmYpDWMXYUndZvdA82pEYnhZRySreFBtCgMvGCLTklggQOlDEjMTrrQ2rKgDZ6HhsEsT+tlBoMLV8DvsoPf3eU3GD1w1tff2OS9gdmzVkY4jyc0v9ld1G7hK5rSaV69AvGPBfdJM7fEAjQCQ7jLCzaxowROrJx42F0IW3qZf4yjLfDQwQUePF7vMczV5vBktjMVx/JWZFuG92CrjHD+Jor1oSx2ofV8E0e0W2rawu+54kaDFPTU4sWDq3Q22M750X1z0XGTK2mn1swg44rxtBTb8iaE9y28JSILIRThoQYUynqGNc3rlK0iFkr8wy4FGhE1umHng6J+Ag8PXDM2HEJ/b9k/0/raZ3lW1uKNpgERPCEgQhcvckxilYBZsAL1xNDoKWIxtxpMUhFbVvnKwCcFWXxx8vrdybuxOGnEY4g+gO3PYci1sw11mmxih9amBybSDHxiGwOzbevhjchT9tSI0zQqctJJWXJKQzLD6zKcpvGkVNCO4DvwrcrJcJsU4Z0vzxtm2KDiubog2MlS5WIvLXJxKxV5JSC5CYslZCYcRjoHXhYvZChT0DX2B5Ycse2W6pptIVBbM1osJoZpF6LbuBK/H4jTNOBl+R07d7PRPK3LG8deWYNUEEaRn0QKmE0+1ljcFve/ZzR5RzusCH/cxFHOoRStYz8czw5qmV3VnYQNh+Is3YaehJml3fE72JvhHTEJcdm2nbPUmS0j8/9ZGzbD2d41Yy9t8YJ6+VtNCjywiv3N6sY08GIojuV1YV6dnF9cCpb03c4v4QwXXAWu8a7RVmeNg5/0DRprnVShiDHXuYPZh0Et0J2+LabexHVBC01m6kMW9c4qhwmP7AmlSCcDxj0HFz3IFxJDpOw6/RPVzkjFY1WHiFhc4QOlOev8kMDCwPHCWTAR0kN3QmgVTqVgOzf755miy7KY6+9ukflrfe46YlFYFGKYQ0YrHcHpn0lp/P3Ry1ek4eVLcw29pBlmKNs/BIsJzKXyl+38yuFWTv+Wb2E3Bg7DIA2SfYshwiDqwx8u8jwyLlMGnIXk63IDuC09sqWUZOtUq3xN9V2yJkpC9oaZXUCfBVB3da12GbxKBAZgIAPxiewIUcJFlgMDy3VN7oBVuW18SAQkqdbKhOwU/gWMYEUX4vE8nuVFpOKRpG/I3lkNNCLtoMjZx2RW9TSF44y3qlrWnzRBYMACVB2rdQmP5Ar8Cb5uumi6lAjkoflPWu9ELibf3cSfWFdEdzaHgOD5gkTKrHn6Xxdnpy8C8yM2XbTKJGMpTNfMGy7p9eNmqjvE6CKaWEX84OTy4Fi6Ve+nLixcrYTV4XWaEI3N8Uv0dHaX0XpvklVQIgdh4GRccAAxLmAaiooLFZ0J9vLt+18mSAY5fnMyPr2cnL27PDk7nbw7H786+YVW47nL9jaan4+Pz87Jujt6jbazCeK/b8PiFjKqrIbyXsmBsdIuZZYvp3QdEdeFVazhN5Fz99YVOeX8ljlnCbAV/gRqxd1Q9kh71OnrXN6cnI6diQOE/KCdk4QzYn4Z+2XZmGKFRPZE38rTSAMQqzCzcHp3RCNcjC8Qct0yHB7rU6vRoucJr3MSFguSWAQNNVgniDEMuPsBtxt5+Gs9/p7ncTINE2Gmc0yyj7SfgIDEKtaQtJQ9V5xWUAnfZs+pkKi7WFnnNSZxTdbvbcLqig11F+r+5EkShfP7JKjhlfeee8Yuiboj1OLAtc3cwGYTZ0QODeeP2O2FlClqhO55VTJvzsURGxmuOUIYxGfvRepX4dTMSI6FM4RTDmX+HIkTrge8LuBmCWe3ZRoSpcck01aCb6HTKzgruy74Xpv9s1M24ODIECvY6ktXtatgZ4smXbX5INQS8QyaWQ3LnvtdpXCywN/OiEPgcngON2ddvoScoNW1Oyh8YLgksmy3E+OKq0X9PKF5efLq1fic8Lq7k/lHzgwpmVuXBIV2pmr92jwVwN0OKxiRa8g6ix1YYKogOQSwzPekqRjEDiGJYvPkd201SaI/jE+A7pA7x+Wk6y1Q7rfYQNhCiBMfUofKYrTNH2Kk2LmcHr0dDxwcFv2EkIv0Cw6SRyLI/7Qnaw2ZG8vmINDLvjjcUqPVU7/hfAkHvvfXSn3QHx7gJwPjNTNEN3947h3dugm2jp5sOPb5n9Nckie0DweQ3pVIRiIrjl1gf6nN8AK6m8szPBfa6Gb4iv7SYgYgS/rjskp+vvCuWveQ6xPisb6mweRFZNSl4f1QJTW/u+K/lae8anN5j/PGrwHftXW6jifMQLkl4UIZT5hnKqwKkfK+CImWNV6yji4aAAk0K/YV/zT2BPXKkhcnVnakP/KLOKxWlJXyhHcYv+wKKRVP+XZeDvqWedgkHSYzhGYroQDVDhCnrpLUIXgiGkUcA8RRv7B2xrwFvhYbTWaPC1Ga9moXXBC/Q9oMCL9L9Nb2ZMs4Id0Nvvpudk1C5ACvFycwcbfLMAWvjNl5qNLgsJ1VwhpKUuaa1daEPOCZYPNMdY78tl7ZbAgJt8VpOtSu84yjdZ8qbEpSdSnSgmcSgjJ//8Pq0Y6SBTeENGOv8+BxHir5C+1OWA5je9/oekMhkCwDB5MUewX72klunahCLkpmlYgHIiFnCmzU4LWNUSGZRT9RHWTQ5DzMbHwhisXlqHwcAJeYZaZoGxA1JxXrSn6/E9/kCEZZkUJYQr3yv4CGvf66z7mzFOkR4/loPDD7/Q/7VwGE7motEop9SrI6/uyEtmh2W6fCqXLl5iQ2ArCIQUrjvvnOPNsMwm5MjcVNCDRz2TxdaQrcSAentQ7sz4P259OrTk9PzJjzYGGWTpH2YnxSrxSIaq1yrIh2n/FB0skyUBmnGQIZinhONpU4PdZ6l5AXGNtQEbZAeh/9Fb8BJ6eCJqyqEDwGoRcj8w0Tui7m2dUWgHWo6gNAddUC5dn68o/gtGA3yxbhafzO2g0brmWz9rnNG7vNaOZrHYuOx9wunMGyjCNrYmecNJrMiHT2iCB/IwZZbqy7M48RKQV73hdix0YYZ42PNTCBFa5o00VMNYVby/fL+tv7LFFxBHUbYT1k8a3R1UafolMMkBizGpiPmLClOhiXCZ76nnEIz7bh/ze4wZpVx/v1tzqvOAlRXlW3CkLKiN+yKlsXVjLCEBiYaS3a/crp2HaT3cMjCGkbltobmRPZInZwQPGeB2S0P+Bx+PrD3hXwYcfbce4N9+3NLsA6q/2wf0jt1vfDAuLBDWlt6s/txgbmsdQZSYQ4gD/rJv7kC3A/YIGf2furfhDFm9lhrd+JZdmIM8wDuJNLfwNRu2MLHLYN7a5yc9yNqKfvuoXeZwlav+R31j1ED9GCkysnCxmwVO4fbllj2dCYXKvL7FRURlU+WHN8LjDnvOYqidlrx2c6xNQqNLXDSmr24Qre8TMWICXnPvsOicNTeD9Kw+U0IlPm0PjDDv2TeMmaJLxLiIc57UblWFsdfUVz8h5xb5gzMQ7zko0m7dmastAAVa3p6NOZBlStBarRC8BDzd071nizEpn8XtaEeltrG9QvWg6mzzyf5uPRBO9U8Z2JIp+0Ywe6D0PeANaSrZqJzMEceV01/RHf7aCb9Mn8VwzpMsYJqq7WZV3kNLDEPGO795rCAf8F2xIbjgBJuOBcRqQ10oT9g72Db4d7/zE8+Iu6R5/0rBQkTOQwEG09a/6ZuySxFBhBSvZ+EfdiD8SiyOuVTTmNJXxQ8pkkwkDte05TZF9IR9vnVFtrE4jzqNUjWgtdjolpnHWRZ+rSV7PRSvmWZBSJA6zD7+LsHkvVjnaAqLCf9cE5O8pjjODXfict7ENDiFcs98VjpCQDToprbXPlOtvgqq8ZuL4g4WSVRIoEIzkEE/BF15hkLMDGlregBvOG2MengauWo68dca+0YyDpN68XN2YX0QgH1yxGSv4zeuCQUDivYlFiVosijGDEMpVFmoKeih1oqQ1ptEJJ5QoxWktfYkrosZHAjFONIPFxhsy8O7r8Qe4OwJlYb9JlQOxIFjMUQI7ccq6z/0O+BPe62ynFwmcP8y7Jjt0bfYJTj4zgOkJ/oIxFIeNABdlKJXNGEdpVUXOUrrHF1MMYimmVQRnO07qKeTKBk1KCBAx2ssuJjDnyFQJrLCZz0+5xkJRRsiDF3031+QRx6PHm7H5V7tI1knXal1wBkZdByCE6n5oNcPnL5OzH/tYUSGqhJheyxkay7746cO3c+OFm6hruuilujy9hPedyLROhrFMYyu0praCoM/+DtxK/T46/8MmOGldOO9zVA64qNyOJ8xtGTveIOfMhP2Id7v2X459O379580VdJtm2N23+3OjASVilqbMUxjpttkVXV6B1KRF5/Y5+aTWHJl/GGfOi+flAHoabh0iYwGiZlISmPqYkh5ZahMG9bRijneFxb71zBLF+JonEXKsJ/ERrni/DhxHlPSIgyd2y50zUS8enPPy+mksaq3hzdvbj+3eTV0cnb96fj20emsMoHxzSf9DN5gSitqsZqk8QM/icq+2IGxITJwkFTmTPI+/ix+nZ6fFY4rFrDNhyWHr2d2Z5S+sVEW4r7I3jCfeimXF7CWd3/WM3nLIsM+f3HG7m+pqVZUOF44xLdi9DixAlEJO0mpDrchdbVaFVxGlYZzMcpBIxzU4zZditDiQ+eHGthffciPMbkPNDUj0wF7noAQyR4fGxE+gUkSCxzrhsIwEi0dEln+SVgzmtgqYuJd3G0uoWzUFlSS/Oc4meFXpMShVGixp3ojg+5OlEuMhisEUG19lXSKd2b5f2SLc9nynqnJ6xiYUiWu8Gji1Z0D1vgw4SuKn4lB/DDNFH9jfDn8Gn06AlrQU/WLpnH5MizziwhbEUY23yz4crK5kqe56KtyMvGom1FpbjJPWW3ATGDYORLXA6gjHrbFGrWE4hWDmbwEpFliWMa7SHUSLNRN8WUITmLo4WcaNGNB5bWMCq03JuDAEEmeLAECY5YcV9PSUvwGzdvdRQhVGsm6KEjJEU40qXHxxignBBZQs+1dxSpUORVjlpdCelRSE5m5jPXjPBxXDG/l2rgNuO3ICenBjs+pgZdJy1qVvNeqkHttkKb14nNdxg5nqk5In5E14Aunvf6ZohJV4MvlNYk4TlC51J9MKzR0OrG6ZvqSzANEwMXHvlZZb2QBv1zpskDjDniNWbo4tLU93l6mgLeh03KCZu3aCDdk1d7+fTh5bmxJqgPQ00OKYuvcPhwVUHSk7zh3rUiPQWwaSSutEcRxtavA7rjuq030hy3i78+JAZU4v3r2lWXc/fZ6P723CM3exQWzzSoNul9Luq0z+ueT2sWXUn3dWy/jkt6UEoK/d5GMps/AqBSOoOtyf+mN6hsoa6fCG+1tMYYCWrJ1jkoVYFsMlY2r2kDCbd8JmwY/G169gxfANqFknaKkysshHmTd0OrVQwaA+CCLUze+PEITJOdsgsInWi39jLqrLK8qGvmn8bkU0sgrha02hVbf3fgS9HMTmPQRgstCCIuoGYoJKLmmd/j4ucU/cCPTxDmodk5DDXtplCjsH5xMk/cQ5Dwc1l0/L+1CA4cbjbWPVAThDUIYWdT2nLsJHYBeu5YTkHe/pOkjhbb1ajaOAWzv8mcVsjpKmQwaiDLOWhsTmK9ngXL443eUkD4vhwkyrKNXcAWFXVnFCfRzY08J5QMRctEaTXGvm9Tg5lHLWOGQ5kFxxBZQ+0xm6qNm8FK1pkSPh3DYOHA+BfagHZZGaVhpMqnyRwPR74hKSkISBJp9XvNSvXKkHifWoaKoFyNKUMGgVIOZyWhulj932xS/gQTZsn1HaUlG0QmYnWQx8ew8vjbjzNMaFdjVvNn70n1lurR0Ua+kssea/CpNA0sS2q+E4pE5VQvWSU0ZQ1DOUIPIMYu+gTeXuMv1nE88f0xOZUIeGW6IyuwiHHmVpwjNztaW67O9S4N/SA+iMHeZq31LCACjdq74rcERh3PGwyKV9e6PrHteYPTpKLb85DcZCeHPjWLD539VwGQ9NklTHM8tW94A+RR7goYoRipnw6Tgw4HL8VBUcy/qh3nESbCa8SLT0vUMvifDz+ZXw8ef3+6PzlBJlAmm43kQfjl15zZhQTYMnbwnKAvVJpTHPu2rZN9hgf8OdD6lrjpGF0dJ8VbHZJ2Zx/W8CB27KXVFG+cWF3Ldt3vz5gzbIdm4kN8JhOLPjArJpVXQKuOmm5IgwmKPVyJLWjtdMzcFPlZ7w1bAvNnKRTJ5tBPXb8upSFOLm8cGdTrxD1kUMV3go55ZJZxlVEnHbYVdiEWWOPsVEn52tXWsxI02zAxAPzk1MOyOkoFHU30+6aCj4K8DON73bch+KfnyfWZmQTuhzYk9xSVYI9rU1aHPOHDsmq8rtGRrTkjurbqb8ADGOSwWbATdpxG+Hn424mwk4eZQPfv9Qb6LiqkDnJdMDDwuG+8cSSRf/xM94b+uFjp87WT++2IADAPweDRghWNx2KVthKCbIODZ+L2FNLU88DsBy4xjvXDaFe4+XrVobZLC0+mQj9MW69yoSnaTRBeb8RRwh9DNl98mFjjxAr9PbtaeQLPbTDuB5LQT5bR866fhq/uehQHCkdWNETrlbB2pCeMBLvimt56Llkl4GNOOHesY0IDz2tUOhtYksubT/GvtPJwHzoXGGgK/M1p3f6gCGZLM2UHj/cp5n6a8rIVmnX7OcbJHFuqC4S37f1X/jciUT5nFw5m/Nx2Kon8rivwdY1HcVuNoT1RA7/ukd188LVXrL2onQXuI1FsGKzUUzhUUbRtZy3xq9ZDxjZ4hDynz34fPRq8v4UOap6DTfq5OLyfHz0tv+Zs8YKaiHMBw4ag9evlb7oAM37qjw0X5WIq+ja4v7n82NkeBgN/tZcmK2nnDsnnR+EVUe/6WpHHcWpXYWet4wSllxazJLz4IFmbik7OQZuvTPw61WcXcyH6Dmd0hynYU3W3jEp6NTru7ysLvM8fV82h8c5liUJ7qGWGKuohZqEmhwtddYWWtBMdE+pD6jaJ1+gwFy4Qsv9b83b5PsBJ1pqsTakVqK2w8Xly5PTyfe/Xo4vUCfOKQDWk7oJzAw/hkUCrlGqgy1vyn8eIYk6ze/AA4R9sXQl0jx8SBNEKVQ+sYHZSLLBjFR0apGEKBdZ4aRfyfIXKOMecs1Q7a1ExiLeySVXTLni23DW2FgoJrdaaWIQVw2Q9PaStbQwigr00KSQo4CbmNWDNl/ZGFsSqtXbFPQSZBF3vPQlpaqoj/H52yZJ8uQl+nDyK2yWpmhfczn9hee/5VMVAdzLfxM2nfyXg8ZDnEW1fuD/Jrglv9kCqeGCncjshBdpYh0h3BWHTt6fXI7brtRCVYtWOU/TmLRRd1xt7KrCcj5oQ+3rHREJ/Dx+ORmf/sRSDwiljlMyQjvOrTUw4ZasGb+aKdsLkmvWcmVci1nAWLTyNxT3BiHhcK6nAB2h3jW1IyF/JJmVosxCg8yXSVWtpT9zEy5Kao8jiHVJOAX6rIC5Hpcg8kR39zBI1figvEaEKFP5HeMdgho0eYjTFrjSWWY2AQfBoA/plT96HWKkJVl3t8RWLOuQsiVspLK3DxqNVKrgSx7z6PTXxlkuThU4+3tPbMBJqS3KNcC0ggcAWT6l5YD5vEKuQuZ49fn4pHMeW1xqpRmfvTI+ny2fFcmqYo8aYn03YQESHvABx3xR2PORUo0PdhFO17LLzB4sDSPf1i3hik+2sB9Il+sUOGTO2fH3cPV0qjICI67Zw8mJ+8y6aTblLjVa3U/wO1iJZ2mZLyWQkOD8HHyFZHzmJCyA8WEa9IRtHp+dXrx/e3L6mn69fXt0+lJQXsqZDZkyh6BMb9C3O4jLZgNgnDD5ssmDXBeOucATR9bcRRyzc2xCFFrhiOfRa+TG/XB29qMdDxJ2czQ7lrynGR7NodS5G8GzYQY4PztngpzT6XEfOReVOUCqlwgwLooa6WqaIgClOZDN0Zgbl8+BHsMSjLOjSC4WIWMiE9aBho0Ya+CbNSi8wpVRbVxLTlcJt/KCniYItm7P/UaNZJjyCRxRRjs8oSWaQ8eb1ZxRs9kmEiJrMlnVtG+omUFp30n4eMrHjollH7opnN7Q+1wGYnvahd/ekg7ANQjCrConTIhrK/z5Jlbm1XFP7DRH7piC3NqdzLWES6yxqk1AYqUPIbw9RtziqT/jFPgtWyDoWIljWT1yHD/XFIUmkeEaXVxbv4n4/veaxIZW4gUtSUn9Si3Qo0oZN9wRN/wwJRxLjVavsyE04eo4BMYU2JQcb842qpSkOatspV++dSPaki4DJEMmfLDOoZye7rTSVL85fKbedQsOHk0420ZN0y5LYHxksB1w58IIpYESm5+UZR2b/acHT7/tg/+vpBCRHY3rahLix3P4z5xzOkyBi8aDJ4BR+BH8A3OmnlP1q9/queWkMJY9uR6SZBtBwtOwycM2q9N0sTFqCyuGkWD/RLHYHnFv0IzV9B1bjdYpAyqKKdckZ5/lqeuXaxHoY34bN+en26JaVqA2x7Caav5mg/teN+noApGjTLQnEk6oKeb4Dh3A47hOEeKszuGD3aIEU8TBLd1sSRBwRGJNXCVlzOfAEysxJIID8z4D7LS0iIpx5XSxVLhx3G2mTJYrzcTTAnq2OqjjV5sJpYlssW8+wiee03Ril4OtRd3XXFVrlR1yW5kp6BYA+t/1S3UmoVWlRyAKGrJo6r548sQb2DItzStc03qkbwass6yZWP1/3WuGQT7rJUMjpRrhrfJG66iwofRH8rwaOm5f2og10OOtwchOTL27VZ0Ca9T3X+uDvf3/4AqmkZtoq5XunePRXbulTQ/3tmUVes7ROLHHnbFYf9di3k6mdg66Ccy7WrPNNZX1gQHkMxRkpqPYOwq9OT4SYjGPrHpjZTY5pwzvH1xldz3bpyTJOl+2zM6EFW26ylWneOLWwBbicZKEeKh8tkgWN1Unp1hW2IrSmyYX3c0OlJr7NnHNF3mqVQ3ApvCNk5P2GyfOaXERqjavvUn0j63kbDHcCQ22yetwdOO+TWhZz8mwqYeta7/zRrvLLZnYcqe/i7vvsPvGwMY0D7eOxdmNkv/xRyeasM3J2MEq/awAe7T1UxBbvy5jfLsmQIKN2P6XYMP2osn/RORyLXq5vYCubsdDUTsNHYTTkh9NJgghTCZ9N6lm43znpitVsEUD3bEtg5CjhlqhMTfrSNZUlOet714XKwaW2FHBlt7FdSiSFGluHKiScuH3bXFyazI3vdOOkcoQfLlvVHbOCYnA4Q+968P+4dXDcGmJ3A13mGN2QSLIVlqPD8IVjo8ELTthuq1T/SfwQ8Xjj/H9NA+LCGRfFPWq2pB6+0/3Hg+Fr8uadXvS+F+VfSnR2UziS5jiF8TRN137Tty8naHtCVUOxV6wH8yBhO4W2NSiwWma41x500X7hZBDs/7pjza5q2E6Mo32PjCEbneQpX06u4vw0C0S6TzFBLfwMXj3NIWtbSuKm+3MqnHuULR0eswQaO8CFHSXPyHU3qXh6OY2Z6CD5tL+D1ts3XXUu+E2uNlhhLLP/FBi6seq0EpidtwJR4Miylwog3uz4ky8b2Ij2Kwe1sHZyJVPYIm6XsjRuSYdzDXs3Y3ou2X7HLuHGeOmMSQVtZKsy2Y7Lz7IbxmvPnjcmqOI8tmgYPrtM/0mQKej9kxmWM6SRJG+Kx3Wv1/AwBrI+dCoXq5Knwftb4sUrsWVuoTc6jLEBivEl4SGv4h2/yHu0tRDhbNIvv0B3bR0U7BJXMxA4OlzBGmqvLDp+qR9h0gTtV834NzDNk9QDhhqp7cJcs6dpDbIFETjFZ1ITosAkvykm5pxq2gLOLefTkBqHadt11liF4dvc9iqzPP2Wxo+/s9qMmpko1x84y8zBPKfr1fyNY+BaS8nL1+96W9bEEJlZISkLiraDyYcbhz7bz76YdP15EQiU4/9WIhvP1nStx/TGA4NF5vDA6kPOVzrmR3T9nMd3YqF8K/KNSvwnAuj1Klf55A0r3yjUxKyWYVvdDlfA+GaoihADTnk80fKGPCa/j6cp6IYM5Rp6NsEH51aB4QClBVpRiWbNhjaL6U5INIyDXp+vfmyBg6yB1uM44eDvU+c4tqcOMShtjSegzeS+VFU2z9Y1HzF5YZLvYt2/Vw+RLQ2QFI1gUtZyI5sB7uEbaaefnBHDiB24gudYf329I1bSZH9Z/aALpe3tI6QnVIJ1Pn0TTcdKUyJc/eDf6Dc9lYGJ0v7B2py9z5LaQ2p9nvKvRJUxUAVCvWTleHdhP2pI6egplZLdW/J2lGLtZ1It6y3rbLufFjBpV75uMCGjiXDxeHtZtvRSL+8d7iuiUMGORV1m1rJ61V1u4Pompp6sg9PIU7XJjE+P/+ySXAO7//FJPA5tbUki3bnNnrbmhaRT3/r1lewfrkH6yM4Cn5bntRut415fCT0j7geJafS2BDIFKVQtJxnuKVHLvRHwmMaF7tSPG83q9O0f2igBTaaDurXrtVo3+jMxWqIJRpbNEncI01yr99fS0KlFlqhQfy5e9vSRDplIS7vV1urQWynqu6OWj1Ndr9bmHi9QqutWOmWaXbKafsP1CnG9+3WK8+yJ7j50shc6xNfayWgtrB2YN4mojStFc/Gx2GlELQ7Z3GubeovnLFPekjzBTJVeAeSZMmoun/wl6+1S3//qcMyN1OI/mXu+JnspDUT+Iu7s+rds/0HXBqdrh9PYHMPOik1u5DmTyhKtkRV2EKQ7TFF/YpoyIcENNlePwQJiSlnVWwwxjkAxh+3FY8haiSmcRW3Cea+PRmI6m8DVixJgv6WTwdSNdvZs4e06m4FdR0CaTJf6DNsjsErVaknesLieYYKxJFWIZ5oaXFbdli/hMp3kWzkfqTXRDWr1m4uCko2gKD4C4NbS9Rrx05V4k2C6rN3RolQ2CLPwNwkWumTlMOhW4GcVUarykMHlINJREArmiRxA+ONGXFYwdD6eqSlBUFg1qqfewaoETtncIAAC/tlGQ2NWqVPbIlIVV5UfZDa5pzJghVI8SzCHHx28RWvgh0eChZaiD2qpOqWtVbi9lMYqzyRzAAz54DTbhR/ZN7efLZNwa5gks8ei/IVWIAje0FAV/G5YlvjX3VV3ekon5VBv4mt27BPZjpKQSub+499IEUiROvV6h+sOv94LemHpXBJ1uvqAJ4GZKjgf4IPwMNOtrPJz+dnp29+7Q+aCW184OMzQaDBmsDsP5Do2OvBqOIA62TCQZfJBPgymWjMpTN/lW+CUF9oCkPAWYNO9i0LC5zBIrQhBLAsQpFUA/CSwbP25UfYRBLs16i7tTzYzClNY0taR6gkt5Vi+87CGubTxkwDM4ZUCgXlG4egI0NDyTMcNqYwf1dZcsGdLwTDHyGFfxpqlJiExs33g3U42rEe4Wo9W+cchOlvpkh0XD393v8Aw9aymD9+AAA=" "$it2_py"; or return 1
        end
        command python3 "$it2_py" $argv
    end
end
