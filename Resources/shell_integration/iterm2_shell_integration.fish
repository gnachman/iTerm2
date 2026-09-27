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


if begin; status --is-interactive; and not functions -q -- iterm2_status; and test "$ITERM_ENABLE_SHELL_INTEGRATION_WITH_TMUX""$TERM" != screen; and test "$ITERM_ENABLE_SHELL_INTEGRATION_WITH_TMUX""$TERM" != screen-256color; and test "$ITERM_ENABLE_SHELL_INTEGRATION_WITH_TMUX""$TERM" != tmux-256color; and test "$TERM" != dumb; and test "$TERM" != linux; end
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
  printf "\033]1337;ShellIntegrationVersion=25;shell=fish\007"
end

# it2 CLI over iTerm2 SSH integration: define it2 (materializing the embedded copy,
# named by content hash, on first use) unless it2 already exists. `type -q` also
# detects an existing function/alias; fish's `command -v` (--search) would not and
# would silently clobber a user-defined it2.
if not type -q it2
    function it2
        set -l it2_py "$HOME/.iterm2/it2.2e1a7f98b497171c.py"
        if not test -f "$it2_py"
            if not command -v python3 > /dev/null 2>&1
                echo "it2: python3 is required" >&2
                return 1
            end
            python3 -c 'import base64,glob,gzip,os,sys,tempfile; d=os.path.expanduser("~/.iterm2"); os.makedirs(d,exist_ok=True); data=gzip.decompress(base64.b64decode(sys.argv[1])); fd,tmp=tempfile.mkstemp(dir=d); os.write(fd,data); os.close(fd); os.replace(tmp,sys.argv[2]); [os.remove(f) for f in glob.glob(os.path.join(d,"it2*.py")) if f!=sys.argv[2]]' "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" "$it2_py"; or return 1
        end
        command python3 "$it2_py" $argv
    end
end
