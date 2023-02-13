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

if begin; status --is-interactive; and not functions -q -- iterm2_status; and test "$ITERM_ENABLE_SHELL_INTEGRATION_WITH_TMUX""$TERM" != screen; and test "$ITERM_ENABLE_SHELL_INTEGRATION_WITH_TMUX""$TERM" != screen-256color; and test "$ITERM_ENABLE_SHELL_INTEGRATION_WITH_TMUX""$TERM" != tmux-256color; and test "$TERM" != dumb; and test "$TERM" != linux; end
  function iterm2_status
    printf "\033]133;D;%s\007" $argv
  end

  # Mark start of prompt
  function iterm2_prompt_mark
    printf "\033]133;A\007"
  end

  # Mark end of prompt
  function iterm2_prompt_end
    printf "\033]133;B\007"
  end

  # Tell terminal to create a mark at this location
  function iterm2_preexec --on-event fish_preexec
    # For other shells we would output status here but we can't do that in fish.
    if test "$TERM_PROGRAM" = "iTerm.app"
      printf "\033]133;C;\r\007"
    else
      printf "\033]133;C;\007"
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

    iterm2_status $last_status
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
      iterm2_fish_mode_prompt
    end

    function fish_prompt --description 'Write out the prompt; do not replace this. Instead, change fish_prompt before sourcing .iterm2_shell_integration.fish, or modify iterm2_fish_prompt instead.'
      # Remove the trailing newline from the original prompt. This is done
      # using the string builtin from fish, but to make sure any escape codes
      # are correctly interpreted, use %b for printf.
      printf "%b" (string join "\n" (iterm2_fish_prompt))

      iterm2_prompt_end
    end
  else
    # fish_mode_prompt is empty or unset.
    function fish_prompt --description 'Write out the mode prompt; do not replace this. Instead, change fish_mode_prompt before sourcing .iterm2_shell_integration.fish, or modify iterm2_fish_mode_prompt instead.'
      iterm2_common_prompt

      # Remove the trailing newline from the original prompt. This is done
      # using the string builtin from fish, but to make sure any escape codes
      # are correctly interpreted, use %b for printf.
      printf "%b" (string join "\n" (iterm2_fish_prompt))

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
  printf "\033]1337;ShellIntegrationVersion=19;shell=fish\007"
end
