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
    printf "\033]1337;ShellIntegrationVersion=19;shell=zsh\007"
  fi
fi

# it2 CLI over iTerm2 SSH integration (see bash for details).
if ! command -v it2 > /dev/null 2>&1; then
  it2() {
    command -v python3 > /dev/null 2>&1 || { printf 'it2: python3 is required\n' >&2; return 1; }
    if [ ! -f "${HOME}/.iterm2/it2.2e1a7f98b497171c.py" ]; then
      python3 -c 'import base64,glob,gzip,os,sys,tempfile; d=os.path.expanduser("~/.iterm2"); os.makedirs(d,exist_ok=True); data=gzip.decompress(base64.b64decode(sys.argv[1])); fd,tmp=tempfile.mkstemp(dir=d); os.write(fd,data); os.close(fd); os.replace(tmp,sys.argv[2]); [os.remove(f) for f in glob.glob(os.path.join(d,"it2*.py")) if f!=sys.argv[2]]' "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" "${HOME}/.iterm2/it2.2e1a7f98b497171c.py" || return 1
    fi
    command python3 "${HOME}/.iterm2/it2.2e1a7f98b497171c.py" "$@"
  }
fi
