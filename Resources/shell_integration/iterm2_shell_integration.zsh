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
  # Inside tmux (TERM=tmux*, or $TMUX set when tmux uses a screen* TERM), tmux Integration passes
  # the escape codes on intact and plain tmux discards them, so this loads; TERM=tmux* also reaches
  # a host sshed to from a tmux pane. So does TERM=screen-256color, which many tmux users set.
  # Other screen* TERMs without $TMUX are screen, or tmux beyond an ssh hop, and are skipped. ITERM_ENABLE_SHELL_INTEGRATION_WITH_TMUX forces it on. In tmux,
  # TERM_PROGRAM is tmux's own.
  if [[ -n "${ITERM_ENABLE_SHELL_INTEGRATION_WITH_TMUX-}" || -n "${TMUX-}" || "${TERM-}" != screen* || "${TERM-}" = screen-256color ]] &&
     [[ -z "${TERM_PROGRAM-}" || "${TERM_PROGRAM-}" = "iTerm.app" || "${LC_TERMINAL-}" = "iTerm2" ||
        ( "${TERM_PROGRAM-}" = "tmux" && ( -n "${TMUX-}" || "${TERM-}" = tmux* ) ) ]] &&
     [[ "${ITERM_SHELL_INTEGRATION_INSTALLED-}" = "" && "$TERM" != linux && "$TERM" != dumb ]]; then
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

    # Percent-encode $1 per RFC 3986, preserving unreserved characters and the path
    # separator. nomultibyte + LC_ALL=C force byte-wise iteration so each UTF-8 byte
    # is encoded individually (matching how the receiver decodes it). Stores the
    # result in the global _iterm2_encoded_path rather than printing it, so the
    # caller reads a variable instead of forking a command substitution per prompt.
    iterm2_encode_path() {
      emulate -L zsh
      setopt nomultibyte
      local _iterm2_path="$1"
      local _iterm2_i _iterm2_ch _iterm2_hexch _iterm2_out=""
      local LC_ALL=C
      for (( _iterm2_i = 1; _iterm2_i <= ${#_iterm2_path}; ++_iterm2_i )); do
        _iterm2_ch="${_iterm2_path[_iterm2_i]}"
        if [[ "$_iterm2_ch" == [/._~A-Za-z0-9-] ]]; then
          _iterm2_out+="$_iterm2_ch"
        else
          printf -v _iterm2_hexch '%02X' "$(( #_iterm2_ch & 0xFF ))"
          _iterm2_out+="%$_iterm2_hexch"
        fi
      done
      _iterm2_encoded_path="$_iterm2_out"
    }

    iterm2_print_state_data() {
      local _iterm2_hostname="${iterm2_hostname-}"
      if [ -z "${iterm2_hostname:-}" ]; then
        _iterm2_hostname=$(hostname -f 2>/dev/null)
      fi
      # Sanitize the authority: a username or hostname with a URL-structural
      # character (/, ?, #, or whitespace) would silently restructure the URL -
      # recording the wrong directory, or (since the machineID query still parses)
      # poisoning localhost detection with a truncated host. Keep only a safe set so
      # a malformed label degrades to a clean name. The username keeps @ (an AD
      # login like alice@corp.com survives, since URL parsers split on the LAST @).
      local _iterm2_user="${USER//[^A-Za-z0-9._@-]/}"
      _iterm2_hostname="${_iterm2_hostname//[^A-Za-z0-9._-]/}"
      # OSC 7: report username, hostname, and working directory as a single file
      # URL. This supersedes the older 1337;RemoteHost and 1337;CurrentDir codes.
      local _iterm2_encoded_path=""
      iterm2_encode_path "$PWD"
      # Append the machine identity (computed once at source time, see below).
      local _iterm2_url="file://${_iterm2_user}@${_iterm2_hostname}${_iterm2_encoded_path}?machineID=${_iterm2_machine_id}"
      printf "\033]7;%s\007" "$_iterm2_url"
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

    # Mark start of a right prompt (RPROMPT or RPS2; Semantic Prompt k=r). The
    # receiver records the right prompt's cells as an excluded subrange on the
    # active primary mark, so they aren't saved as part of the command, and drops
    # the subrange if zsh later erases the right prompt or draws the command over
    # it.
    iterm2_right_prompt_mark() {
      printf "\033]133;P;k=r;aid=%s\007" "$ITERM2_CURRENT_AID"
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

      iterm2_decorate_right_prompts
    }

    # Put the right prompts back to their raw values, but only if they still
    # hold what iterm2_decorate_right_prompts made of them. Anything else was
    # set since then by the user or a plugin (e.g., an async theme updating
    # RPROMPT from a zle callback) and is left alone.
    iterm2_undecorate_right_prompts() {
      if [[ "${RPROMPT-}" == "${ITERM2_DECORATED_RPROMPT-}" ]]; then
        RPROMPT="${ITERM2_PRECMD_RPROMPT-}"
      fi
      if [[ "${RPS2-}" == "${ITERM2_DECORATED_RPS2-}" ]]; then
        RPS2="${ITERM2_PRECMD_RPS2-}"
      fi
    }

    # Wrap the right prompts with k=r, saving their raw values for
    # iterm2_preexec to restore. Skip an empty one, since there is nothing to
    # mark, and one that already contains a 133;P mark, since a second, nested
    # mark would confuse the receiver. That guards against a theme that marks
    # its own right prompt (as some do for Warp) or a mark added by hand.
    # ITERM2_SQUELCH_RPROMPT_MARK opts out.
    iterm2_decorate_right_prompts() {
      # After ^C, iterm2_preexec didn't run, so the right prompts may still be
      # wrapped from the previous prompt. Start from their raw values.
      iterm2_undecorate_right_prompts
      ITERM2_PRECMD_RPROMPT="${RPROMPT-}"
      ITERM2_PRECMD_RPS2="${RPS2-}"
      if [[ "${ITERM2_SQUELCH_RPROMPT_MARK-}" == "" ]]; then
        if [[ -n "${RPROMPT-}" && $RPROMPT != *"133;P"* ]]; then
          RPROMPT="%{$(iterm2_right_prompt_mark)%}$RPROMPT%{$(iterm2_prompt_end)%}"
        fi
        if [[ -n "${RPS2-}" && $RPS2 != *"133;P"* ]]; then
          RPS2="%{$(iterm2_right_prompt_mark)%}$RPS2%{$(iterm2_prompt_end)%}"
        fi
      fi
      ITERM2_DECORATED_RPROMPT="${RPROMPT-}"
      ITERM2_DECORATED_RPS2="${RPS2-}"
    }

    # Install Shell Integration & Utilities used to alias it2ssh to a copy in .iterm2, which
    # hides the newer it2ssh iTerm2 puts on PATH. Remove that alias, and only that alias, when
    # the it2ssh PATH finds first is the one inside iTerm2's app bundle. Done at the first
    # prompt because the installer appended the alias after this script.
    iterm2_drop_stale_it2ssh_alias() {
      [[ "${aliases[it2ssh]-}" == */.iterm2/it2ssh ]] || return 0
      local found
      found="$(whence -p it2ssh)" || return 0
      [[ "$found" == */Contents/Resources/utilities/it2ssh ]] && unalias it2ssh
      return 0
    }

    iterm2_precmd() {
      local STATUS="$?"
      if [[ -z "${ITERM2_CHECKED_IT2SSH_ALIAS-}" ]]; then
        ITERM2_CHECKED_IT2SSH_ALIAS=1
        iterm2_drop_stale_it2ssh_alias
      fi
      if [ -z "${ITERM2_SHOULD_DECORATE_PROMPT-}" ]; then
        # You pressed ^C while entering a command (iterm2_preexec did not run)
        iterm2_before_cmd_executes
        if [ "$PS1" != "${ITERM2_DECORATED_PS1-}" ]; then
          # PS1 changed, perhaps in another precmd. See issue 9938.
          ITERM2_SHOULD_DECORATE_PROMPT="1"
        elif [ "${RPROMPT-}" != "${ITERM2_DECORATED_RPROMPT-}" ] || [ "${RPS2-}" != "${ITERM2_DECORATED_RPS2-}" ]; then
          # Only a right prompt changed. PS1 still has our escape sequences, so
          # wrap just the right prompts rather than decorating PS1 a second time.
          iterm2_decorate_right_prompts
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
      # Set the prompts back to their raw values prior to executing the command.
      PS1="$ITERM2_PRECMD_PS1"
      PS2="$ITERM2_PRECMD_PS2"
      iterm2_undecorate_right_prompts
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

    # Machine identity for OSC 7 localhost detection, computed ONCE and cached in a
    # NON-EXPORTED shell variable (never `export`/`typeset -x`, so it cannot cross
    # ssh) as "1:<hmac>". We HMAC kern.bootsessionuuid with a fixed protocol key
    # rather than sending the raw per-boot UUID; iTerm2 HMACs its own the same way
    # and compares. The sysctl and openssl run once here, not per prompt. A known
    # non-Darwin host can't be this Mac, so it sends the empty value ("1:"); a Darwin
    # failure, or an OS we cannot determine at all (empty $OSTYPE), sends "0:"
    # (identity unavailable, so the receiver falls back to hostname matching).
    if [ -z "${_iterm2_machine_id+set}" ]; then
      case "${OSTYPE-}" in
        darwin*)
          _iterm2_bsid=$(sysctl -n kern.bootsessionuuid 2>/dev/null)
          _iterm2_machine_id="0:"
          if [ -n "$_iterm2_bsid" ]; then
            _iterm2_hmac=$(printf '%s' "$_iterm2_bsid" | /usr/bin/openssl dgst -sha256 -hmac "iterm2-osc7-machine-id" 2>/dev/null | awk '{print $NF}')
            [ -n "$_iterm2_hmac" ] && _iterm2_machine_id="1:$_iterm2_hmac"
            unset _iterm2_hmac
          fi
          unset _iterm2_bsid
          ;;
        "")
          _iterm2_machine_id="0:"
          ;;
        *)
          _iterm2_machine_id="1:"
          ;;
      esac
    fi


    [[ -z ${precmd_functions-} ]] && precmd_functions=()
    precmd_functions=($precmd_functions iterm2_precmd)

    [[ -z ${preexec_functions-} ]] && preexec_functions=()
    preexec_functions=($preexec_functions iterm2_preexec)

    iterm2_print_state_data
    printf "\033]1337;ShellIntegrationVersion=23;shell=zsh\007"
  fi
fi

# Put iTerm2's uploaded it2 on PATH, ahead of the shell function below. Exported, so a program
# started from this shell passes it on: a Claude Code hook runs through `sh -c` and an agent's
# Bash tool does too, and neither sees a shell function. Done here rather than from the app
# because the real PATH is only known in the login shell; the conductor cannot express a prepend
# (its setenv does no re-expansion) and an absolute value there would break conductor.sh itself.
# Guarded on the directory existing, so a host iTerm2 never uploaded to keeps a clean PATH. Moved
# to the front if it is already on PATH, so iTerm2's it2 wins over any other (a login profile's
# path_helper or a `brew shellenv` may have put other directories ahead of it), and never
# duplicated, so re-sourcing does not stack copies.
if [[ -d "${HOME}/.iterm2/bin" ]]; then
  # Quoted, (@) and [@] so the user's options (KSH_ARRAYS, SH_WORD_SPLIT, GLOB_SUBST) can't
  # truncate PATH, split an entry with a space, or treat $HOME as a pattern.
  path=("${HOME}/.iterm2/bin" "${(@)path[@]:#"${HOME}/.iterm2/bin"}")
  export PATH
fi

# it2 CLI over iTerm2 SSH integration (see bash for details).
if ! command -v it2 > /dev/null 2>&1; then
  it2() {
    command -v python3 > /dev/null 2>&1 || { printf 'it2: python3 is required\n' >&2; return 1; }
    if [ ! -f "${HOME}/.iterm2/it2.360a8dc76dd1793c.py" ]; then
      python3 -c 'import base64,gzip,os,sys,tempfile; d=os.path.expanduser("~/.iterm2"); os.makedirs(d,exist_ok=True); data=gzip.decompress(base64.b64decode(sys.argv[1])); fd,tmp=tempfile.mkstemp(dir=d); os.write(fd,data); os.close(fd); os.replace(tmp,sys.argv[2])' "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" "${HOME}/.iterm2/it2.360a8dc76dd1793c.py" || return 1
    fi
    command python3 "${HOME}/.iterm2/it2.360a8dc76dd1793c.py" "$@"
  }
fi
