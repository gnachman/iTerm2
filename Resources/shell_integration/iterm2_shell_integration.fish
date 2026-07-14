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
        set -l it2_py "$HOME/.iterm2/it2.e86e52cd6f0ff62a.py"
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
