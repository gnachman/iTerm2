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

if [[ -o interactive ]]; then
  # Don't run in IDE terminals. TERM_PROGRAM is set by the local terminal but not
  # forwarded over SSH. LC_TERMINAL is set by iTerm2 and may be forwarded over SSH.
  if [ \( -z "${TERM_PROGRAM-}" -o "${TERM_PROGRAM-}" = "iTerm.app" -o "${LC_TERMINAL-}" = "iTerm2" \) -a "${ITERM_ENABLE_SHELL_INTEGRATION_WITH_TMUX-}""$TERM" != "tmux-256color" -a "${ITERM_ENABLE_SHELL_INTEGRATION_WITH_TMUX-}""$TERM" != "screen" -a "${ITERM_SHELL_INTEGRATION_INSTALLED-}" = "" -a "$TERM" != linux -a "$TERM" != dumb ]; then
    ITERM_SHELL_INTEGRATION_INSTALLED=Yes
    ITERM2_SHOULD_DECORATE_PROMPT="1"

    # OSC 133 aid: per-command identifier the receiver uses to target a
    # specific mark for D-by-aid (and cascade-close when an outer command
    # like ssh dies before its inner remote shell's D arrives). The salt
    # is rolled once at shell-source time; the counter increments per
    # prompt cycle in iterm2_precmd.
    typeset -g ITERM2_AID_SALT="${RANDOM}${RANDOM}"
    typeset -gi ITERM2_AID_COUNTER=0
    # Pre-seeded so emissions before the first iterm2_precmd (e.g.
    # iterm2_print_state_data at install time) have a defined aid value
    # rather than the empty string.
    typeset -g ITERM2_CURRENT_AID="${ITERM2_AID_SALT}-0"

    # Indicates start of command output. Runs just before command executes.
    iterm2_before_cmd_executes() {
      if [ "$TERM_PROGRAM" = "iTerm.app" ]; then
        printf "\033]133;C;aid=%s\r\007" "$ITERM2_CURRENT_AID"
      else
        printf "\033]133;C;aid=%s\007" "$ITERM2_CURRENT_AID"
      fi
    }

    iterm2_set_user_var() {
      printf "\033]1337;SetUserVar=%s=%s\007" "$1" $(printf "%s" "$2" | base64 | tr -d '\n')
    }

    # Users can write their own version of this method. It should call
    # iterm2_set_user_var but not produce any other output.
    # e.g., iterm2_set_user_var currentDirectory $PWD
    # Accessible in iTerm2 (in a badge now, elsewhere in the future) as
    # \(user.currentDirectory).
    whence -v iterm2_print_user_vars > /dev/null 2>&1
    if [ $? -ne 0 ]; then
      iterm2_print_user_vars() {
          true
      }
    fi

    iterm2_print_state_data() {
      local _iterm2_hostname="${iterm2_hostname-}"
      if [ -z "${iterm2_hostname:-}" ]; then
        _iterm2_hostname=$(hostname -f 2>/dev/null)
      fi
      printf "\033]1337;RemoteHost=%s@%s\007" "$USER" "${_iterm2_hostname-}"
      printf "\033]1337;CurrentDir=%s\007" "$PWD"
      iterm2_print_user_vars
    }

    # Report return code of command; runs after command finishes but before prompt.
    # Uses the OLD aid (the one in effect for the just-finished command). The
    # counter increments AFTER this call so the new A/B/C cycle starts fresh.
    iterm2_after_cmd_executes() {
      printf "\033]133;D;%s;aid=%s\007" "$STATUS" "$ITERM2_CURRENT_AID"
      iterm2_print_state_data
    }

    # Mark start of prompt
    iterm2_prompt_mark() {
      printf "\033]133;A;aid=%s\007" "$ITERM2_CURRENT_AID"
    }

    # Mark start of a PS2 continuation prompt (Semantic Prompt k=s — non-editable
    # secondary). Receiver-side (iTerm2 r600+) treats this as a non-mark-creating
    # signal that paste-helpers can use to advance past PS2 lines (issue 5749) and
    # that records the PS2 prefix cells as an excluded subrange on the active
    # primary mark, so selection / share / AI consumers can subtract them.
    iterm2_ps2_mark() {
      printf "\033]133;A;k=s;aid=%s\007" "$ITERM2_CURRENT_AID"
    }

    # Mark end of prompt
    iterm2_prompt_end() {
      printf "\033]133;B;aid=%s\007" "$ITERM2_CURRENT_AID"
    }

    # There are three possible paths in life.
    #
    # 1) A command is entered at the prompt and you press return.
    #    The following steps happen:
    #    * iterm2_preexec is invoked
    #      * PS1 is set to ITERM2_PRECMD_PS1
    #      * ITERM2_SHOULD_DECORATE_PROMPT is set to 1
    #    * The command executes (possibly reading or modifying PS1)
    #    * iterm2_precmd is invoked
    #      * ITERM2_PRECMD_PS1 is set to PS1 (as modified by command execution)
    #      * PS1 gets our escape sequences added to it
    #    * zsh displays your prompt
    #    * You start entering a command
    #
    # 2) You press ^C while entering a command at the prompt.
    #    The following steps happen:
    #    * (iterm2_preexec is NOT invoked)
    #    * iterm2_precmd is invoked
    #      * iterm2_before_cmd_executes is called since we detected that iterm2_preexec was not run
    #      * (ITERM2_PRECMD_PS1 and PS1 are not messed with, since PS1 already has our escape
    #        sequences and ITERM2_PRECMD_PS1 already has PS1's original value)
    #    * zsh displays your prompt
    #    * You start entering a command
    #
    # 3) A new shell is born.
    #    * PS1 has some initial value, either zsh's default or a value set before this script is sourced.
    #    * iterm2_precmd is invoked
    #      * ITERM2_SHOULD_DECORATE_PROMPT is initialized to 1
    #      * ITERM2_PRECMD_PS1 is set to the initial value of PS1
    #      * PS1 gets our escape sequences added to it
    #    * Your prompt is shown and you may begin entering a command.
    #
    # Invariants:
    # * ITERM2_SHOULD_DECORATE_PROMPT is 1 during and just after command execution, and "" while the prompt is
    #   shown and until you enter a command and press return.
    # * PS1 does not have our escape sequences during command execution
    # * After the command executes but before a new one begins, PS1 has escape sequences and
    #   ITERM2_PRECMD_PS1 has PS1's original value.
    iterm2_decorate_prompt() {
      # This should be a raw PS1 without iTerm2's stuff. It could be changed during command
      # execution.
      ITERM2_PRECMD_PS1="$PS1"
      ITERM2_PRECMD_PS2="$PS2"
      ITERM2_SHOULD_DECORATE_PROMPT=""

      # Add our escape sequences just before the prompt is shown.
      # Use ITERM2_SQUELCH_MARK for people who can't modify PS1 directly, like powerlevel9k users.
      # This is gross but I had a heck of a time writing a correct if statetment for zsh 5.0.2.
      local PREFIX=""
      if [[ $PS1 == *"$(iterm2_prompt_mark)"* ]]; then
        PREFIX=""
      elif [[ "${ITERM2_SQUELCH_MARK-}" != "" ]]; then
        PREFIX=""
      else
        PREFIX="%{$(iterm2_prompt_mark)%}"
      fi
      PS1="$PREFIX$PS1%{$(iterm2_prompt_end)%}"
      ITERM2_DECORATED_PS1="$PS1"

      # Wrap PS2 with k=s so the receiver can subtract the PS2 prefix cells from
      # the typed-command region and so paste-helpers can advance past PS2 lines.
      # Skip if PS2 already contains our mark (user re-sourced this script) or if
      # the user has opted out via ITERM2_SQUELCH_PS2_MARK. The wrap is idempotent
      # in steady state because iterm2_preexec restores PS2 from
      # ITERM2_PRECMD_PS2 before the next cycle.
      if [[ $PS2 != *"$(iterm2_ps2_mark)"* ]] && [[ "${ITERM2_SQUELCH_PS2_MARK-}" == "" ]]; then
        PS2="%{$(iterm2_ps2_mark)%}$PS2%{$(iterm2_prompt_end)%}"
      fi
      ITERM2_DECORATED_PS2="$PS2"
    }

    iterm2_precmd() {
      local STATUS="$?"
      if [ -z "${ITERM2_SHOULD_DECORATE_PROMPT-}" ]; then
        # You pressed ^C while entering a command (iterm2_preexec did not run)
        iterm2_before_cmd_executes
        if [ "$PS1" != "${ITERM2_DECORATED_PS1-}" ]; then
          # PS1 changed, perhaps in another precmd. See issue 9938.
          ITERM2_SHOULD_DECORATE_PROMPT="1"
        fi
      fi

      iterm2_after_cmd_executes "$STATUS"

      # Roll the per-command aid AFTER D for the previous command has fired
      # and BEFORE the new prompt is decorated. PS1's iterm2_prompt_mark
      # gets evaluated each time the prompt is drawn (it's inside %{ %}),
      # so the next A read will pick up the new value.
      ITERM2_AID_COUNTER=$((ITERM2_AID_COUNTER + 1))
      ITERM2_CURRENT_AID="${ITERM2_AID_SALT}-${ITERM2_AID_COUNTER}"

      if [ -n "$ITERM2_SHOULD_DECORATE_PROMPT" ]; then
        iterm2_decorate_prompt
      fi
    }

    # This is not run if you press ^C while entering a command.
    iterm2_preexec() {
      # Set PS1 and PS2 back to their raw values prior to executing the command.
      PS1="$ITERM2_PRECMD_PS1"
      PS2="$ITERM2_PRECMD_PS2"
      ITERM2_SHOULD_DECORATE_PROMPT="1"
      iterm2_before_cmd_executes
    }

    # If hostname -f is slow on your system set iterm2_hostname prior to
    # sourcing this script. We know it is fast on macOS so we don't cache
    # it. That lets us handle the hostname changing like when you attach
    # to a VPN.
    if [ -z "${iterm2_hostname-}" ]; then
      if [ "$(uname)" != "Darwin" ]; then
        iterm2_hostname=`hostname -f 2>/dev/null`
        # Some flavors of BSD (i.e. NetBSD and OpenBSD) don't have the -f option.
        if [ $? -ne 0 ]; then
          iterm2_hostname=`hostname`
        fi
      fi
    fi

    [[ -z ${precmd_functions-} ]] && precmd_functions=()
    precmd_functions=($precmd_functions iterm2_precmd)

    [[ -z ${preexec_functions-} ]] && preexec_functions=()
    preexec_functions=($preexec_functions iterm2_preexec)

    iterm2_print_state_data
    printf "\033]1337;ShellIntegrationVersion=17;shell=zsh\007"
  fi
fi

# it2 CLI over iTerm2 SSH integration (see bash for details).
if ! command -v it2 > /dev/null 2>&1; then
  it2() {
    command -v python3 > /dev/null 2>&1 || { printf 'it2: python3 is required\n' >&2; return 1; }
    if [ ! -f "${HOME}/.iterm2/it2.4a5c7f87cc6e339b.py" ]; then
      python3 -c 'import base64,glob,gzip,os,sys,tempfile; d=os.path.expanduser("~/.iterm2"); os.makedirs(d,exist_ok=True); data=gzip.decompress(base64.b64decode(sys.argv[1])); fd,tmp=tempfile.mkstemp(dir=d); os.write(fd,data); os.close(fd); os.replace(tmp,sys.argv[2]); [os.remove(f) for f in glob.glob(os.path.join(d,"it2*.py")) if f!=sys.argv[2]]' "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" "${HOME}/.iterm2/it2.4a5c7f87cc6e339b.py" || return 1
    fi
    command python3 "${HOME}/.iterm2/it2.4a5c7f87cc6e339b.py" "$@"
  }
fi
