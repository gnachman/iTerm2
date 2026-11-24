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
    if [ ! -f "${HOME}/.iterm2/it2.4f5d263fc6b8b1a2.py" ]; then
      python3 -c 'import base64,gzip,os,sys,tempfile; d=os.path.expanduser("~/.iterm2"); os.makedirs(d,exist_ok=True); data=gzip.decompress(base64.b64decode(sys.argv[1])); fd,tmp=tempfile.mkstemp(dir=d); os.write(fd,data); os.close(fd); os.replace(tmp,sys.argv[2])' "H4sIAAAAAAACA7V9a3fbRpL2d/6KXnjyCpyQ0MVOdlYOfVaRaUcbW/KR5FzWo0OBBEghAgEOLpY1efPft56qaqBBUrJnZtcfZAJo9KW67lVdePJvu3VZ7E6TbDfOPprVfXWTZ097nuedx8u8is11Uh1cm1maxFll5nlhksu4WB6Yi4sfTJJV8aIIqyTPgl7v55s4M/d5bcIiNmV5sxOhQW5Cc5OXlfmYhPruTrn+9sBUN7GZ5VlUz6q82Cl78yJcxkWwujfxp1VeVCV1U2fJJxPlyzDJTJnPbuPK+KuwuqGezJ9OLg8mF2fHP/apq7AyqyL/lMSlofGp616az8JUhw/M5U1CT5Ls3pRVlCbTYZ6l93aNv9UlL/QuLCIatVh8NF+bil5MMuqC5ljFn6qe9Guk32U4u0myeGDubmJaOx78uYjD9M+GgEevLJdhFpmqiGPjx8tpHEUxYKPz6ZuizsoemkRJSQua3TQTN0fvTkwZFx/j4jkmm9fVLv0XF8Vu/Cmp6BaNszTTcHaLZcV2EVlMb/SmdZJiDRl3U8R/q2NaW1KVcTofEAgN9xDe02hFQvuTEhQA2/tsZu4SAixmcHGXzPHSAbY4oeURaKt8lqfGrwBHHfG74Qsjm6Z70x+YNM4W1c1wVcTz5BMtmZ+Xh72eoX8f9s30nhCsul/FVx+eycU0WQzjLEpoyqvwPs3DSDu5+qDXV73e+5Uu29exaWgF5SF3vfPDjvlh/ObNGf3+rcyzQ/O7nfTAZHk2o63Cxg7M7C4a8OYOTFKGVXVPt/K0HJgiv6O/RBIDgD3J/pCOj3fM8dHp8fiNMfFyVd0b41+cvD45vXxu6pJWOL0nlMgWQ9rRLMkWu8s8SwihLQ6U/V7vZX6X2fkrLdH8ZSV2/mc75uLy5dn7S2OK8I5BU8qTMT8Zn59vPPllx4x/Obk07ZpneRT/QZd+GgKlAfznQOAsnoHosLsZDZyXMeZ1TuhB21saJgbs/DtmBsCQLCJiMEQpRVjcG2CqPnsa/PvXxl/UYRESXRAAaK9LWshhDx0oPjCaVGF6y1gdprT26J6RnkiacJmQqx+A5fR6yRLETvhcxt8+s1dYjv2dl/ZXeVNXSdpcJQsiz+aKMbC5qgpiK81VPSVkmMVl29N987NKlnGvJ7gzMlPvB6/3xFwAxxKGl6BVYJkgU2YpCySCKwFVQCdPaVkD/km4T5gB9pXFd7RWRVkmrzCj3om/pWHGbJAGKSsCjsnnRjEIJHoTpnOBVFnleRSY7+vlih4Q5uaLmGZVtNQarlbEPZ+YY8tLiS++jJf1p8BSwE8yT2ZWzprMgthqSZBbUo8YOGwY1yzMsrzCjKjjWV4UhD+EIhiT+FFgjrQHnkSWG88O5QEdorBiEBE6JHEaMVBmeZ2BpZcCqaD37vzs8uz47M3kp/H5xcnZKQF/v6eUhn049npKECOTF5HvnXn9nhKC3hnTHSYAvf6Frmm+RyaKZymJJGU/yk9MOM0/xrJzwE7CyYqahNgoYepoDThEMfNDPzS0klDY1DIpgcTUvbwgXQqf6/MKqfuCOiRGEvIGkVAiYBf36JGIYFrP57ibQ8owcJ6Z18n3pn56QNLkU7KslwH1/jrO4iKviRNN41lIeMSDLRJCU5ouycK7bCirmoVFkTDxxoY2ZVVXRK4ikpLZDbaQujAEhwVkULBA7xDthMIloy3Wcw3EC4HJwsa4i/5znp+y3yHaMZnQKNRlmt8x/KgFJB6YRZpS32AJYK2AL0vURQJKoWkky2VMDL6iuc3SOCwMCTPikFAt6Gk+/ZjQggm9pvmiLhW0Qe/t0S+TV+dHb8eTN+PT15c/0C4ffPOt+bPZ3zt4pv/RsGfE26Fw0CQJvLrz2KKuNBlACArzJD6S10BLgt9HFm7E19P7wJzM7aqwz7yukjY+GtqugBGMGwMjc68zGmuVZyV3FMcFiUBAChvCSFHWxTzEBDNdtNI79U+AnxLe3QI/CBQQ3wbMhMaffRSV5t34nXn279+Y2zhelXRfscmXHQ5TkuflHc2SJJeSG/ELsIKqSIfHfVV7opjYeExYGROMo5wAcHp2CbYBpi86RxKlsbkLE9H3cCcjlUfIh3Q3Be5waELq3RV35trKu+FwnmMm1w66QrmgngnucXUXE+8RdYCI/+jXN2dHLyfnY/pzefJ2LHT+dA/0e1nUMZA4Fb2Klb/qhrEQpEvAjkjbJJ1hwt0FrKmQ2kiKFMlZsCNpXbLCgy4g36jjVU6IP02xw6RyEDAtHotAJ66b0WwLgBFLY3lJLUpQm05AphUqY0mwMmoKbKEOA3plQmKJ1FxDGt3sVuXEPA0XKhmquqApEg2Am4IbE8gxRFxZ7Yz1OJ0h8W3pWpeKHZC9p3fubu6xVqAQLjOSxXF0yOvBG0b0ZBXu3GmV1zQtVlmIaVDPsiiRWoxwusq1OdC0gt4EnQIsI/OKMI9kZi+K587kfIjggZlDuxtY6htNPU9VnEWaT4ld2H74XjKnGYIkQqJiX9+B/lXoS/hnqW9kfwVxBkXH9+pqPvwLMX20UhwdyQRIgRcdIFiRoux7L048Vk7tGH15CZK+EtLBHk1jEGILQkUf0TQa9ABnFQjlU1YHjAdhqevytGPBlLuYbSNVJYiXgNCI8u8KIhEWuYLD/JIDYtAA3yMsbSEBCAdoRDTv64K/tlCRFc1hs6TOOw/sG5jMJP4UzirdN1IPIuoR/H90SuihG/AEXPHaPrkGCwSDC4jsSeJnyczv8w3awuWqD3wD21fz7ucfzt6MmZ+aJdtYSZaUN8A/KKJ2gJhsKWF6pNpYwQKqx6yndUR3IXTBv1UKMa2EpoQoIjtmdpvGVmUBqzTQSKvKItkTCIO4GPIQzOnQTRGYn0WdMWGzctluViWJ7c1qUnyyqpF9YJmQuD6brgRmoo0dHUJ3g9dKMg6Sj4iZFN6YjRXL6a10TjDcYo0vMg2XfUGG2U2dEQMZmQ9XfN2CZGQyviMY1t5/YfbabSfKahYF7kCgwa62DfBPgTtqmw43drfzAvWq73w3ckez/4owKS0AAwWb71kCZuA0Q8WfZsyyvO4QiuOVfVvGa9swXGjK3A5b6jcQ6Lurx4q5bXeWwoIZFt0uy4C2l0jF56u2qxa+wxFzEOe5dkY8LvgtT/QRLKuWxFrW2BAUjHYXXW5CEVqKZSR2VnVBsio+fABNeD+LJTRWqCHarViYaG61eH9dNvct4UC1iSMW8qpNsvBnIgXgWJcNunx1g2N807c8XNvQvLo45gB70IJcGPRI3/qwJ/itGvXI8u06czi3Nt0//Oaqb1+gcfWdF2ZdV2ynEK9IlhMOko5w2Cj4oor5282EryJFzdLq5aQPM0Do1eCvmWe+0qb9zyxUsVAab0BFBSUhj4MXjQisszS5jRtVzNmlwQP663PSn+ssWme8MNEaNkiydkE8w9IgDLlNzggkvOMRprGwUnDsmG0ExnCH/Q6V/eoI1nIqCTlTi65qOoGHW07AevhAOD8vA7vyXctnw6Lq6xzEr6Uorto0qUFYZcNKeOEiOaqccNs0Jgv9WpBZQjpoCbErzIMQC1vJnTZ9jDbl2tdmm566KZZbBWWDRqzx0YhW+0NwB4i2qozf5ZgDcyk/xsDTgTm74B/9L8NqS9yAgagYX0VDtmEFh6y68FmkbpfVku66dtGBwzb2zapEO29Zry6o++YqLEtLNnboL+QoXYrSl5ULWz8uKeZ/j/2GCZf3ZSDeVTuI6OPtPXaTRVYnjD/FMzGjxYie57l58f+G18xSN/oM5iSas5xwiCViaY4qIpRpXcW8cNCdOgR1lCQbqotK39AufwrTOlY0YDcTuxb03XmYpDWMXYUndZvdA82pEYnhZRySreFBtCgMvGCLTklggQOlDEjMTrrQ2rKgDZ6HhsEsT+tlBoMLV8DvsoPf3eU3GD1w1tff2OS9gdmzVkY4jyc0v9ld1G7hK5rSaV69AvGPBfdJM7fEAjQCQ7jLCzaxowROrJx42F0IW3qZf4yjLfDQwQUePF7vMczV5vBktjMVx/JWZFuG92CrjHD+Jor1oSx2ofV8E0e0W2rawu+54kaDFPTU4sWDq3Q22M750X1z0XGTK2mn1swg44rxtBTb8iaE9y28JSILIRThoQYUynqGNc3rlK0iFkr8wy4FGhE1umHng6J+Ag8PXDM2HEJ/b9k/0/raZ3lW1uKNpgERPCEgQhcvckxilYBZsAL1xNDoKWIxtxpMUhFbVvnKwCcFWXxx8vrdybuxOGnEY4g+gO3PYci1sw11mmxih9amBybSDHxiGwOzbevhjchT9tSI0zQqctJJWXJKQzLD6zKcpvGkVNCO4DvwrcrJcJsU4Z0vzxtm2KDiubog2MlS5WIvLXJxKxV5JSC5CYslZCYcRjoHXhYvZChT0DX2B5Ycse2W6pptIVBbM1osJoZpF6LbuBK/H4jTNOBl+R07d7PRPK3LG8deWYNUEEaRn0QKmE0+1ljcFve/ZzR5RzusCH/cxFHOoRStYz8czw5qmV3VnYQNh+Is3YaehJml3fE72JvhHTEJcdm2nbPUmS0j8/9ZGzbD2d41Yy9t8YJ6+VtNCjywiv3N6sY08GIojuV1YV6dnF9cCpb03c4v4QwXXAWu8a7RVmeNg5/0DRprnVShiDHXuYPZh0Et0J2+LabexHVBC01m6kMW9c4qhwmP7AmlSCcDxj0HFz3IFxJDpOw6/RPVzkjFY1WHiFhc4QOlOev8kMDCwPHCWTAR0kN3QmgVTqVgOzf755miy7KY6+9ukflrfe46YlFYFGKYQ0YrHcHpn0lp/P3Ry1ek4eVLcw29pBlmKNs/BIsJzKXyl+38yuFWTv+Wb2E3Bg7DIA2SfYshwiDqwx8u8jwyLlMGnIXk63IDuC09sqWUZOtUq3xN9V2yJkpC9oaZXUCfBVB3da12GbxKBAZgIAPxiewIUcJFlgMDy3VN7oBVuW18SAQkqdbKhOwU/gWMYEUX4vE8nuVFpOKRpG/I3lkNNCLtoMjZx2RW9TSF44y3qlrWnzRBYMACVB2rdQmP5Ar8Cb5uumi6lAjkoflPWu9ELibf3cSfWFdEdzaHgOD5gkTKrHn6Xxdnpy8C8yM2XbTKJGMpTNfMGy7p9eNmqjvE6CKaWEX84OTy4Fi6Ve+nLixcrYTV4XWaEI3N8Uv0dHaX0XpvklVQIgdh4GRccAAxLmAaiooLFZ0J9vLt+18mSAY5fnMyPr2cnL27PDk7nbw7H786+YVW47nL9jaan4+Pz87Jujt6jbazCeK/b8PiFjKqrIbyXsmBsdIuZZYvp3QdEdeFVazhN5Fz99YVOeX8ljlnCbAV/gRqxd1Q9kh71OnrXN6cnI6diQOE/KCdk4QzYn4Z+2XZmGKFRPZE38rTSAMQqzCzcHp3RCNcjC8Qct0yHB7rU6vRoucJr3MSFguSWAQNNVgniDEMuPsBtxt5+Gs9/p7ncTINE2Gmc0yyj7SfgIDEKtaQtJQ9V5xWUAnfZs+pkKi7WFnnNSZxTdbvbcLqig11F+r+5EkShfP7JKjhlfeee8Yuiboj1OLAtc3cwGYTZ0QODeeP2O2FlClqhO55VTJvzsURGxmuOUIYxGfvRepX4dTMSI6FM4RTDmX+HIkTrge8LuBmCWe3ZRoSpcck01aCb6HTKzgruy74Xpv9s1M24ODIECvY6ktXtatgZ4smXbX5INQS8QyaWQ3LnvtdpXCywN/OiEPgcngON2ddvoScoNW1Oyh8YLgksmy3E+OKq0X9PKF5efLq1fic8Lq7k/lHzgwpmVuXBIV2pmr92jwVwN0OKxiRa8g6ix1YYKogOQSwzPekqRjEDiGJYvPkd201SaI/jE+A7pA7x+Wk6y1Q7rfYQNhCiBMfUofKYrTNH2Kk2LmcHr0dDxwcFv2EkIv0Cw6SRyLI/7Qnaw2ZG8vmINDLvjjcUqPVU7/hfAkHvvfXSn3QHx7gJwPjNTNEN3947h3dugm2jp5sOPb5n9Nckie0DweQ3pVIRiIrjl1gf6nN8AK6m8szPBfa6Gb4iv7SYgYgS/rjskp+vvCuWveQ6xPisb6mweRFZNSl4f1QJTW/u+K/lae8anN5j/PGrwHftXW6jifMQLkl4UIZT5hnKqwKkfK+CImWNV6yji4aAAk0K/YV/zT2BPXKkhcnVnakP/KLOKxWlJXyhHcYv+wKKRVP+XZeDvqWedgkHSYzhGYroQDVDhCnrpLUIXgiGkUcA8RRv7B2xrwFvhYbTWaPC1Ga9moXXBC/Q9oMCL9L9Nb2ZMs4Id0Nvvpudk1C5ACvFycwcbfLMAWvjNl5qNLgsJ1VwhpKUuaa1daEPOCZYPNMdY78tl7ZbAgJt8VpOtSu84yjdZ8qbEpSdSnSgmcSgjJ//8Pq0Y6SBTeENGOv8+BxHir5C+1OWA5je9/oekMhkCwDB5MUewX72klunahCLkpmlYgHIiFnCmzU4LWNUSGZRT9RHWTQ5DzMbHwhisXlqHwcAJeYZaZoGxA1JxXrSn6/E9/kCEZZkUJYQr3yv4CGvf66z7mzFOkR4/loPDD7/Q/7VwGE7motEop9SrI6/uyEtmh2W6fCqXLl5iQ2ArCIQUrjvvnOPNsMwm5MjcVNCDRz2TxdaQrcSAentQ7sz4P259OrTk9PzJjzYGGWTpH2YnxSrxSIaq1yrIh2n/FB0skyUBmnGQIZinhONpU4PdZ6l5AXGNtQEbZAeh/9Fb8BJ6eCJqyqEDwGoRcj8w0Tui7m2dUWgHWo6gNAddUC5dn68o/gtGA3yxbhafzO2g0brmWz9rnNG7vNaOZrHYuOx9wunMGyjCNrYmecNJrMiHT2iCB/IwZZbqy7M48RKQV73hdix0YYZ42PNTCBFa5o00VMNYVby/fL+tv7LFFxBHUbYT1k8a3R1UafolMMkBizGpiPmLClOhiXCZ76nnEIz7bh/ze4wZpVx/v1tzqvOAlRXlW3CkLKiN+yKlsXVjLCEBiYaS3a/crp2HaT3cMjCGkbltobmRPZInZwQPGeB2S0P+Bx+PrD3hXwYcfbce4N9+3NLsA6q/2wf0jt1vfDAuLBDWlt6s/txgbmsdQZSYQ4gD/rJv7kC3A/YIGf2furfhDFm9lhrd+JZdmIM8wDuJNLfwNRu2MLHLYN7a5yc9yNqKfvuoXeZwlav+R31j1ED9GCkysnCxmwVO4fbllj2dCYXKvL7FRURlU+WHN8LjDnvOYqidlrx2c6xNQqNLXDSmr24Qre8TMWICXnPvsOicNTeD9Kw+U0IlPm0PjDDv2TeMmaJLxLiIc57UblWFsdfUVz8h5xb5gzMQ7zko0m7dmastAAVa3p6NOZBlStBarRC8BDzd071nizEpn8XtaEeltrG9QvWg6mzzyf5uPRBO9U8Z2JIp+0Ywe6D0PeANaSrZqJzMEceV01/RHf7aCb9Mn8VwzpMsYJqq7WZV3kNLDEPGO795rCAf8F2xIbjgBJuOBcRqQ10oT9g72Db4d7/zE8+Iu6R5/0rBQkTOQwEG09a/6ZuySxFBhBSvZ+EfdiD8SiyOuVTTmNJXxQ8pkkwkDte05TZF9IR9vnVFtrE4jzqNUjWgtdjolpnHWRZ+rSV7PRSvmWZBSJA6zD7+LsHkvVjnaAqLCf9cE5O8pjjODXfict7ENDiFcs98VjpCQDToprbXPlOtvgqq8ZuL4g4WSVRIoEIzkEE/BF15hkLMDGlregBvOG2MengauWo68dca+0YyDpN68XN2YX0QgH1yxGSv4zeuCQUDivYlFiVosijGDEMpVFmoKeih1oqQ1ptEJJ5QoxWktfYkrosZHAjFONIPFxhsy8O7r8Qe4OwJlYb9JlQOxIFjMUQI7ccq6z/0O+BPe62ynFwmcP8y7Jjt0bfYJTj4zgOkJ/oIxFIeNABdlKJXNGEdpVUXOUrrHF1MMYimmVQRnO07qKeTKBk1KCBAx2ssuJjDnyFQJrLCZz0+5xkJRRsiDF3031+QRx6PHm7H5V7tI1knXal1wBkZdByCE6n5oNcPnL5OzH/tYUSGqhJheyxkay7746cO3c+OFm6hruuilujy9hPedyLROhrFMYyu0praCoM/+DtxK/T46/8MmOGldOO9zVA64qNyOJ8xtGTveIOfMhP2Id7v2X459O379580VdJtm2N23+3OjASVilqbMUxjpttkVXV6B1KRF5/Y5+aTWHJl/GGfOi+flAHoabh0iYwGiZlISmPqYkh5ZahMG9bRijneFxb71zBLF+JonEXKsJ/ERrni/DhxHlPSIgyd2y50zUS8enPPy+mksaq3hzdvbj+3eTV0cnb96fj20emsMoHxzSf9DN5gSitqsZqk8QM/icq+2IGxITJwkFTmTPI+/ix+nZ6fFY4rFrDNhyWHr2d2Z5S+sVEW4r7I3jCfeimXF7CWd3/WM3nLIsM+f3HG7m+pqVZUOF44xLdi9DixAlEJO0mpDrchdbVaFVxGlYZzMcpBIxzU4zZditDiQ+eHGthffciPMbkPNDUj0wF7noAQyR4fGxE+gUkSCxzrhsIwEi0dEln+SVgzmtgqYuJd3G0uoWzUFlSS/Oc4meFXpMShVGixp3ojg+5OlEuMhisEUG19lXSKd2b5f2SLc9nynqnJ6xiYUiWu8Gji1Z0D1vgw4SuKn4lB/DDNFH9jfDn8Gn06AlrQU/WLpnH5MizziwhbEUY23yz4crK5kqe56KtyMvGom1FpbjJPWW3ATGDYORLXA6gjHrbFGrWE4hWDmbwEpFliWMa7SHUSLNRN8WUITmLo4WcaNGNB5bWMCq03JuDAEEmeLAECY5YcV9PSUvwGzdvdRQhVGsm6KEjJEU40qXHxxignBBZQs+1dxSpUORVjlpdCelRSE5m5jPXjPBxXDG/l2rgNuO3ICenBjs+pgZdJy1qVvNeqkHttkKb14nNdxg5nqk5In5E14Aunvf6ZohJV4MvlNYk4TlC51J9MKzR0OrG6ZvqSzANEwMXHvlZZb2QBv1zpskDjDniNWbo4tLU93l6mgLeh03KCZu3aCDdk1d7+fTh5bmxJqgPQ00OKYuvcPhwVUHSk7zh3rUiPQWwaSSutEcRxtavA7rjuq030hy3i78+JAZU4v3r2lWXc/fZ6P723CM3exQWzzSoNul9Luq0z+ueT2sWXUn3dWy/jkt6UEoK/d5GMps/AqBSOoOtyf+mN6hsoa6fCG+1tMYYCWrJ1jkoVYFsMlY2r2kDCbd8JmwY/G169gxfANqFknaKkysshHmTd0OrVQwaA+CCLUze+PEITJOdsgsInWi39jLqrLK8qGvmn8bkU0sgrha02hVbf3fgS9HMTmPQRgstCCIuoGYoJKLmmd/j4ucU/cCPTxDmodk5DDXtplCjsH5xMk/cQ5Dwc1l0/L+1CA4cbjbWPVAThDUIYWdT2nLsJHYBeu5YTkHe/pOkjhbb1ajaOAWzv8mcVsjpKmQwaiDLOWhsTmK9ngXL443eUkD4vhwkyrKNXcAWFXVnFCfRzY08J5QMRctEaTXGvm9Tg5lHLWOGQ5kFxxBZQ+0xm6qNm8FK1pkSPh3DYOHA+BfagHZZGaVhpMqnyRwPR74hKSkISBJp9XvNSvXKkHifWoaKoFyNKUMGgVIOZyWhulj932xS/gQTZsn1HaUlG0QmYnWQx8ew8vjbjzNMaFdjVvNn70n1lurR0Ua+kssea/CpNA0sS2q+E4pE5VQvWSU0ZQ1DOUIPIMYu+gTeXuMv1nE88f0xOZUIeGW6IyuwiHHmVpwjNztaW67O9S4N/SA+iMHeZq31LCACjdq74rcERh3PGwyKV9e6PrHteYPTpKLb85DcZCeHPjWLD539VwGQ9NklTHM8tW94A+RR7goYoRipnw6Tgw4HL8VBUcy/qh3nESbCa8SLT0vUMvifDz+ZXw8ef3+6PzlBJlAmm43kQfjl15zZhQTYMnbwnKAvVJpTHPu2rZN9hgf8OdD6lrjpGF0dJ8VbHZJ2Zx/W8CB27KXVFG+cWF3Ldt3vz5gzbIdm4kN8JhOLPjArJpVXQKuOmm5IgwmKPVyJLWjtdMzcFPlZ7w1bAvNnKRTJ5tBPXb8upSFOLm8cGdTrxD1kUMV3go55ZJZxlVEnHbYVdiEWWOPsVEn52tXWsxI02zAxAPzk1MOyOkoFHU30+6aCj4K8DON73bch+KfnyfWZmQTuhzYk9xSVYI9rU1aHPOHDsmq8rtGRrTkjurbqb8ADGOSwWbATdpxG+Hn424mwk4eZQPfv9Qb6LiqkDnJdMDDwuG+8cSSRf/xM94b+uFjp87WT++2IADAPweDRghWNx2KVthKCbIODZ+L2FNLU88DsBy4xjvXDaFe4+XrVobZLC0+mQj9MW69yoSnaTRBeb8RRwh9DNl98mFjjxAr9PbtaeQLPbTDuB5LQT5bR866fhq/uehQHCkdWNETrlbB2pCeMBLvimt56Llkl4GNOOHesY0IDz2tUOhtYksubT/GvtPJwHzoXGGgK/M1p3f6gCGZLM2UHj/cp5n6a8rIVmnX7OcbJHFuqC4S37f1X/jciUT5nFw5m/Nx2Kon8rivwdY1HcVuNoT1RA7/ukd188LVXrL2onQXuI1FsGKzUUzhUUbRtZy3xq9ZDxjZ4hDynz34fPRq8v4UOap6DTfq5OLyfHz0tv+Zs8YKaiHMBw4ag9evlb7oAM37qjw0X5WIq+ja4v7n82NkeBgN/tZcmK2nnDsnnR+EVUe/6WpHHcWpXYWet4wSllxazJLz4IFmbik7OQZuvTPw61WcXcyH6Dmd0hynYU3W3jEp6NTru7ysLvM8fV82h8c5liUJ7qGWGKuohZqEmhwtddYWWtBMdE+pD6jaJ1+gwFy4Qsv9b83b5PsBJ1pqsTakVqK2w8Xly5PTyfe/Xo4vUCfOKQDWk7oJzAw/hkUCrlGqgy1vyn8eIYk6ze/AA4R9sXQl0jx8SBNEKVQ+sYHZSLLBjFR0apGEKBdZ4aRfyfIXKOMecs1Q7a1ExiLeySVXTLni23DW2FgoJrdaaWIQVw2Q9PaStbQwigr00KSQo4CbmNWDNl/ZGFsSqtXbFPQSZBF3vPQlpaqoj/H52yZJ8uQl+nDyK2yWpmhfczn9hee/5VMVAdzLfxM2nfyXg8ZDnEW1fuD/Jrglv9kCqeGCncjshBdpYh0h3BWHTt6fXI7brtRCVYtWOU/TmLRRd1xt7KrCcj5oQ+3rHREJ/Dx+ORmf/sRSDwiljlMyQjvOrTUw4ZasGb+aKdsLkmvWcmVci1nAWLTyNxT3BiHhcK6nAB2h3jW1IyF/JJmVosxCg8yXSVWtpT9zEy5Kao8jiHVJOAX6rIC5Hpcg8kR39zBI1figvEaEKFP5HeMdgho0eYjTFrjSWWY2AQfBoA/plT96HWKkJVl3t8RWLOuQsiVspLK3DxqNVKrgSx7z6PTXxlkuThU4+3tPbMBJqS3KNcC0ggcAWT6l5YD5vEKuQuZ49fn4pHMeW1xqpRmfvTI+ny2fFcmqYo8aYn03YQESHvABx3xR2PORUo0PdhFO17LLzB4sDSPf1i3hik+2sB9Il+sUOGTO2fH3cPV0qjICI67Zw8mJ+8y6aTblLjVa3U/wO1iJZ2mZLyWQkOD8HHyFZHzmJCyA8WEa9IRtHp+dXrx/e3L6mn69fXt0+lJQXsqZDZkyh6BMb9C3O4jLZgNgnDD5ssmDXBeOucATR9bcRRyzc2xCFFrhiOfRa+TG/XB29qMdDxJ2czQ7lrynGR7NodS5G8GzYQY4PztngpzT6XEfOReVOUCqlwgwLooa6WqaIgClOZDN0Zgbl8+BHsMSjLOjSC4WIWMiE9aBho0Ya+CbNSi8wpVRbVxLTlcJt/KCniYItm7P/UaNZJjyCRxRRjs8oSWaQ8eb1ZxRs9kmEiJrMlnVtG+omUFp30n4eMrHjollH7opnN7Q+1wGYnvahd/ekg7ANQjCrConTIhrK/z5Jlbm1XFP7DRH7piC3NqdzLWES6yxqk1AYqUPIbw9RtziqT/jFPgtWyDoWIljWT1yHD/XFIUmkeEaXVxbv4n4/veaxIZW4gUtSUn9Si3Qo0oZN9wRN/wwJRxLjVavsyE04eo4BMYU2JQcb842qpSkOatspV++dSPaki4DJEMmfLDOoZye7rTSVL85fKbedQsOHk0420ZN0y5LYHxksB1w58IIpYESm5+UZR2b/acHT7/tg/+vpBCRHY3rahLix3P4z5xzOkyBi8aDJ4BR+BH8A3OmnlP1q9/queWkMJY9uR6SZBtBwtOwycM2q9N0sTFqCyuGkWD/RLHYHnFv0IzV9B1bjdYpAyqKKdckZ5/lqeuXaxHoY34bN+en26JaVqA2x7Caav5mg/teN+noApGjTLQnEk6oKeb4Dh3A47hOEeKszuGD3aIEU8TBLd1sSRBwRGJNXCVlzOfAEysxJIID8z4D7LS0iIpx5XSxVLhx3G2mTJYrzcTTAnq2OqjjV5sJpYlssW8+wiee03Ril4OtRd3XXFVrlR1yW5kp6BYA+t/1S3UmoVWlRyAKGrJo6r548sQb2DItzStc03qkbwass6yZWP1/3WuGQT7rJUMjpRrhrfJG66iwofRH8rwaOm5f2og10OOtwchOTL27VZ0Ca9T3X+uDvf3/4AqmkZtoq5XunePRXbulTQ/3tmUVes7ROLHHnbFYf9di3k6mdg66Ccy7WrPNNZX1gQHkMxRkpqPYOwq9OT4SYjGPrHpjZTY5pwzvH1xldz3bpyTJOl+2zM6EFW26ylWneOLWwBbicZKEeKh8tkgWN1Unp1hW2IrSmyYX3c0OlJr7NnHNF3mqVQ3ApvCNk5P2GyfOaXERqjavvUn0j63kbDHcCQ22yetwdOO+TWhZz8mwqYeta7/zRrvLLZnYcqe/i7vvsPvGwMY0D7eOxdmNkv/xRyeasM3J2MEq/awAe7T1UxBbvy5jfLsmQIKN2P6XYMP2osn/RORyLXq5vYCubsdDUTsNHYTTkh9NJgghTCZ9N6lm43znpitVsEUD3bEtg5CjhlqhMTfrSNZUlOet714XKwaW2FHBlt7FdSiSFGluHKiScuH3bXFyazI3vdOOkcoQfLlvVHbOCYnA4Q+968P+4dXDcGmJ3A13mGN2QSLIVlqPD8IVjo8ELTthuq1T/SfwQ8Xjj/H9NA+LCGRfFPWq2pB6+0/3Hg+Fr8uadXvS+F+VfSnR2UziS5jiF8TRN137Tty8naHtCVUOxV6wH8yBhO4W2NSiwWma41x500X7hZBDs/7pjza5q2E6Mo32PjCEbneQpX06u4vw0C0S6TzFBLfwMXj3NIWtbSuKm+3MqnHuULR0eswQaO8CFHSXPyHU3qXh6OY2Z6CD5tL+D1ts3XXUu+E2uNlhhLLP/FBi6seq0EpidtwJR4Miylwog3uz4ky8b2Ij2Kwe1sHZyJVPYIm6XsjRuSYdzDXs3Y3ou2X7HLuHGeOmMSQVtZKsy2Y7Lz7IbxmvPnjcmqOI8tmgYPrtM/0mQKej9kxmWM6SRJG+Kx3Wv1/AwBrI+dCoXq5Knwftb4sUrsWVuoTc6jLEBivEl4SGv4h2/yHu0tRDhbNIvv0B3bR0U7BJXMxA4OlzBGmqvLDp+qR9h0gTtV834NzDNk9QDhhqp7cJcs6dpDbIFETjFZ1ITosAkvykm5pxq2gLOLefTkBqHadt11liF4dvc9iqzPP2Wxo+/s9qMmpko1x84y8zBPKfr1fyNY+BaS8nL1+96W9bEEJlZISkLiraDyYcbhz7bz76YdP15EQiU4/9WIhvP1nStx/TGA4NF5vDA6kPOVzrmR3T9nMd3YqF8K/KNSvwnAuj1Klf55A0r3yjUxKyWYVvdDlfA+GaoihADTnk80fKGPCa/j6cp6IYM5Rp6NsEH51aB4QClBVpRiWbNhjaL6U5INIyDXp+vfmyBg6yB1uM44eDvU+c4tqcOMShtjSegzeS+VFU2z9Y1HzF5YZLvYt2/Vw+RLQ2QFI1gUtZyI5sB7uEbaaefnBHDiB24gudYf329I1bSZH9Z/aALpe3tI6QnVIJ1Pn0TTcdKUyJc/eDf6Dc9lYGJ0v7B2py9z5LaQ2p9nvKvRJUxUAVCvWTleHdhP2pI6egplZLdW/J2lGLtZ1It6y3rbLufFjBpV75uMCGjiXDxeHtZtvRSL+8d7iuiUMGORV1m1rJ61V1u4Pompp6sg9PIU7XJjE+P/+ySXAO7//FJPA5tbUki3bnNnrbmhaRT3/r1lewfrkH6yM4Cn5bntRut415fCT0j7geJafS2BDIFKVQtJxnuKVHLvRHwmMaF7tSPG83q9O0f2igBTaaDurXrtVo3+jMxWqIJRpbNEncI01yr99fS0KlFlqhQfy5e9vSRDplIS7vV1urQWynqu6OWj1Ndr9bmHi9QqutWOmWaXbKafsP1CnG9+3WK8+yJ7j50shc6xNfayWgtrB2YN4mojStFc/Gx2GlELQ7Z3GubeovnLFPekjzBTJVeAeSZMmoun/wl6+1S3//qcMyN1OI/mXu+JnspDUT+Iu7s+rds/0HXBqdrh9PYHMPOik1u5DmTyhKtkRV2EKQ7TFF/YpoyIcENNlePwQJiSlnVWwwxjkAxh+3FY8haiSmcRW3Cea+PRmI6m8DVixJgv6WTwdSNdvZs4e06m4FdR0CaTJf6DNsjsErVaknesLieYYKxJFWIZ5oaXFbdli/hMp3kWzkfqTXRDWr1m4uCko2gKD4C4NbS9Rrx05V4k2C6rN3RolQ2CLPwNwkWumTlMOhW4GcVUarykMHlINJREArmiRxA+ONGXFYwdD6eqSlBUFg1qqfewaoETtncIAAC/tlGQ2NWqVPbIlIVV5UfZDa5pzJghVI8SzCHHx28RWvgh0eChZaiD2qpOqWtVbi9lMYqzyRzAAz54DTbhR/ZN7efLZNwa5gks8ei/IVWIAje0FAV/G5YlvjX3VV3ekon5VBv4mt27BPZjpKQSub+499IEUiROvV6h+sOv94LemHpXBJ1uvqAJ4GZKjgf4IPwMNOtrPJz+dnp29+7Q+aCW184OMzQaDBmsDsP5Do2OvBqOIA62TCQZfJBPgymWjMpTN/lW+CUF9oCkPAWYNO9i0LC5zBIrQhBLAsQpFUA/CSwbP25UfYRBLs16i7tTzYzClNY0taR6gkt5Vi+87CGubTxkwDM4ZUCgXlG4egI0NDyTMcNqYwf1dZcsGdLwTDHyGFfxpqlJiExs33g3U42rEe4Wo9W+cchOlvpkh0XD393v8Aw9aymD9+AAA=" "${HOME}/.iterm2/it2.4f5d263fc6b8b1a2.py" || return 1
    fi
    command python3 "${HOME}/.iterm2/it2.4f5d263fc6b8b1a2.py" "$@"
  }
fi
