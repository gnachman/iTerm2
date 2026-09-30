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
        set -l it2_py "$HOME/.iterm2/it2.212690748889c7bb.py"
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
