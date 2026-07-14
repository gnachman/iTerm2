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
    if [ ! -f "${HOME}/.iterm2/it2.e86e52cd6f0ff62a.py" ]; then
      python3 -c 'import base64,glob,gzip,os,sys,tempfile; d=os.path.expanduser("~/.iterm2"); os.makedirs(d,exist_ok=True); data=gzip.decompress(base64.b64decode(sys.argv[1])); fd,tmp=tempfile.mkstemp(dir=d); os.write(fd,data); os.close(fd); os.replace(tmp,sys.argv[2]); [os.remove(f) for f in glob.glob(os.path.join(d,"it2*.py")) if f!=sys.argv[2]]' "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" "${HOME}/.iterm2/it2.e86e52cd6f0ff62a.py" || return 1
    fi
    command python3 "${HOME}/.iterm2/it2.e86e52cd6f0ff62a.py" "$@"
  }
fi
