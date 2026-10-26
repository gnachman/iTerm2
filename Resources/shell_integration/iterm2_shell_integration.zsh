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
    printf "\033]1337;ShellIntegrationVersion=20;shell=zsh\007"
  fi
fi

# Put iTerm2's uploaded it2 on PATH, ahead of the shell function below. Exported, so a program
# started from this shell passes it on: a Claude Code hook runs through `sh -c` and an agent's
# Bash tool does too, and neither sees a shell function. Done here rather than from the app
# because the real PATH is only known in the login shell; the conductor cannot express a prepend
# (its setenv does no re-expansion) and an absolute value there would break conductor.sh itself.
# Guarded on the directory existing, so a host iTerm2 never uploaded to keeps a clean PATH, and
# on absence from PATH, so re-sourcing does not stack duplicates.
case ":${PATH}:" in
  *":${HOME}/.iterm2/bin:"*) ;;
  *) [ -d "${HOME}/.iterm2/bin" ] && PATH="${HOME}/.iterm2/bin:${PATH}" && export PATH ;;
esac

# it2 CLI over iTerm2 SSH integration (see bash for details).
if ! command -v it2 > /dev/null 2>&1; then
  it2() {
    command -v python3 > /dev/null 2>&1 || { printf 'it2: python3 is required\n' >&2; return 1; }
    if [ ! -f "${HOME}/.iterm2/it2.9ec2bce60a6b86bf.py" ]; then
      python3 -c 'import base64,gzip,os,sys,tempfile; d=os.path.expanduser("~/.iterm2"); os.makedirs(d,exist_ok=True); data=gzip.decompress(base64.b64decode(sys.argv[1])); fd,tmp=tempfile.mkstemp(dir=d); os.write(fd,data); os.close(fd); os.replace(tmp,sys.argv[2])' "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" "${HOME}/.iterm2/it2.9ec2bce60a6b86bf.py" || return 1
    fi
    command python3 "${HOME}/.iterm2/it2.9ec2bce60a6b86bf.py" "$@"
  }
fi
