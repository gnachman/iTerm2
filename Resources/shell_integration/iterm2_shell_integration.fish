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
      if not set -q -g iterm2_hostname
        printf "\033]1337;RemoteHost=%s@%s\007\033]1337;CurrentDir=%s\007" $USER (hostname -f 2>/dev/null) $PWD
      else
        printf "\033]1337;RemoteHost=%s@%s\007\033]1337;CurrentDir=%s\007" $USER $iterm2_hostname $PWD
      end

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

    iterm2_write_remotehost_currentdir_uservars
  end
  printf "\033]1337;ShellIntegrationVersion=22;shell=fish\007"
end

# it2 CLI over iTerm2 SSH integration: define it2 (materializing the embedded copy,
# named by content hash, on first use) unless it2 already exists. `type -q` also
# detects an existing function/alias; fish's `command -v` (--search) would not and
# would silently clobber a user-defined it2.
if not type -q it2
    function it2
        set -l it2_py "$HOME/.iterm2/it2.4a5c7f87cc6e339b.py"
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
