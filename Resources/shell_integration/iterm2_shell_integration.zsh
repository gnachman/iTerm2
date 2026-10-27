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
    if [ ! -f "${HOME}/.iterm2/it2.f1f13ef87d320f31.py" ]; then
      python3 -c 'import base64,gzip,os,sys,tempfile; d=os.path.expanduser("~/.iterm2"); os.makedirs(d,exist_ok=True); data=gzip.decompress(base64.b64decode(sys.argv[1])); fd,tmp=tempfile.mkstemp(dir=d); os.write(fd,data); os.close(fd); os.replace(tmp,sys.argv[2])' "H4sIAAAAAAACA7V96XfbVpLvd/4Vd+DOE9ghIVtZpkcOfZ4i04kmtuQjyUn6uHUokABJRCDAxmJZncn//upXVRe44CK7u+f5g0wSwF3q1r7hyX8c1mVxOE2ywzj7YNYP1TLPvup5nncZr/IqNrdJdXRrZmkSZ5WZ54VJruNidWSurn40SVbFiyKskjwLer1flnFmHvLahEVsynJ5EOGG3IRmmZeV+ZCE+uxBufn0wFTL2MzyLKpnVV4clL15Ea7iIlg/mPjjOi+qkoaps+SjifJVmGSmzGd3cWX8dVgtaSTzp7Pro8nVxelPfRoqrMy6yD8mcWlofhq6l+azMNXpA3O9TOhKkj2YsorSZDrMs/TB7vG3uuSN3odFRLMWiw/mS1PRg0lGQ9Aaq/hj1ZNxjYy7CmfLJIsH5n4Z095x4c9FHKZ/NgQ8emS1CrPIVEUcGz9eTeMoigEbXU/fFHVW9nBLlJS0odmyWbg5eXtmyrj4EBfPsdi8rg7pv7goDuOPSUU/0TwrMw1nd9hWbDeRxfREb1onKfaQ8TBF/Pc6pr0lVRmn8wGB0PAI4QPNViR0PilBAbB9yGbmPiHAYgVX98kcDx3hiBPaHoG2ymd5avwKcNQZvxu+MHJoejb9gUnjbFEth+sinicfact8vTzu9Qz9e//MTB8IwaqHdXzz/mv5Mk0WwziLElryOnxI8zDSQW7e6/ebXu/dWrft69w0tYLymIc++PHA/Dh+/fqCPv9W5tmx+d0uemCyPJvRUeFgB2Z2Hw34cAcmKcOqeqCf8rQcmCK/p79EEgOAPcn+kIFPD8zpyfnp+LUx8WpdPRjjX539cHZ+/dzUJe1w+kAokS2GdKJZki0OV3mWEEJbHCj7vd7L/D6z61daovXLTuz6Lw7M1fXLi3fXxhThPYOmlCtjvjK+vNy68uuBGf96dm3aPc/yKP6DvvppCJQG8J8DgbN4BqLD6WY0cV7GWNcloQcdb2mYGHDyb5kZAEOyiIjBEKUUYfFggKl67avgP780/qIOi5DoggBAZ13SRo57GEDxgdGkCtM7xuowpb1HD4z0RNKEy4Rc/QAsp9dLViB2wucy/vZr+w3bsZ/z0n4ql3WVpM23ZEHk2XxjDGy+VQWxleZbPSVkmMVlO9JD87FKVnGvJ7gzMlPvR6/3xFwBxxKGl6BVYJkgU2YpGySCKwFVQCdPaVsD/ki4T5gB9pXF97RXRVkmrzCj0Ym/pWHGbJAmKSsCjsnnRjEIJLoM07lAqqzyPArM9/VqTRcIc/NFTKsqWmoN12vink/MqeWlxBdfxqv6Y2Ap4GdZJzMrZ09mQWy1JMitaERMHDaMaxZmWV5hRTTwLC8Kwh9CEcxJ/CgwJzoCLyLLjWen8oAOUVgxiAgdkjiNGCizvM7A0kuBVNB7e3lxfXF68Xry8/jy6uzinID/rKeUhnM49XpKECOTF5HvXXj9nhKC/jKmX5gA9Puv9J3We2KieJaSSFL2o/zEhNP8QywnB+wknKzolhAHJUwddwMOUcz80A8N7SQUNrVKSiAxDS8PyJDC5/q8Qxq+oAGJkYR8QCSUCNjFA0YkIpjW8zl+zSFlGDhfmx+S70391RFJk4/Jql4FNPoPcRYXeU2caBrPQsIjnmyREJrSckkW3mdD2dUsLIqEiTc2dCjruiJyFZGUzJY4QhrCEBwWkEHBAqNDtBMKl4y22M8tEC8EJgsb4yH6z3l9yn6HuI/JhGahIdP8nuFHd0DigVmkKY0NlgDWCviyRF0koBRaRrJaxcTgK1rbLI3DwpAwIw4J1YKu5tMPCW2Y0GuaL+pSQRv03pz8Onl1efJmPHk9Pv/h+kc65aNvvjV/Ns+eHn2t/9G0F8TboXDQIgm8evI4oq40GUAICvMkPpLXQEuC3wcWbsTX04fAnM3trnDOvK+SDj4a2qGAEYwbAyNrrzOaa51nJQ8UxwWJQEAKB8JIUdbFPMQCM9200juNT4CfEt7dAT8IFBDfBsyE5p99EJXm7fit+fo/vzF3cbwu6XfFJl9OOExJnpf3tEqSXEpuxC/ACqoiHZ72Ve2JYmLjMWFlTDCOcgLA+cU12AaYvugcSZTG5j5MRN/DLxmpPEI+pLspcIdDE9Lorrgzt1beDYfzHCu5ddAVygWNTHCPq/uYeI+oA0T8J399fXHycnI5pj/XZ2/GQudfPQX9Xhd1DCRORa9i5a9aMhaCdAnYEWmbpDNMeLiANRVSG0mRIjkLdiR3l6zwYAjINxp4nRPiT1OcMKkcBEyLxyLQietmtNoCYMTWWF7SHSWoTRcgywqVsSTYGd0KbKEBA3pkQmKJ1FxDGt3sTuXEPA0XKhmquqAlEg2Am4IbE8gxRVxZ7Yz1OF0h8W0ZWreKE5Czp2fulw/YK1AIXzOSxXF0zPvBE0b0ZBXuPGiV17QsVlmIadDIsimRWoxwusuNNdCygt4EgwIsI/OKMI9kZi+K587ifIjggZlDuxtY6htNPU9VnEWaT4ld2HH4t2ROKwRJhETFvj4D/avQh/DPUt/IfgriDIqO79XVfPgXYvq4S3F0JAsgBV50gGBNirLvvTjzWDm1c/TlIUj6SkgHZzSNQYgtCBV9RNNo0AOcVSCUT1kdMB6Epe7L04EFU+5jto1UlSBeAkIjyr8viERY5AoO80MOiEED/BthaQsJQDjATUTzvm74SwsV2dEcNkvqPLPn3MBkJvHHcFbpuZF6ENGI4P+jc0IPPYAn4Iq39sotWCAYXEBkTxI/S2Z+n3+gI1yt+8A3sH0173758eL1mPmpWbGNlWRJuQT+QRG1E8RkSwnTI9XGChZQPVY9rSP6FUIX/FulENNKaEqIIrJjZndpbFUWsEoDjbSqLJI9gTCIiyFPwZwOwxSB+UXUGRM2O5fjZlWS2N6sJsUnqxrZB5YJieuz6UpgJto40Cn0NHivJOMg+YiYSeGN2VixnN5K5wTTLTb4ItNw2RdkmC3rjBjIyLy/4e8tSEYm418Ew9rfX5in7bETZTWbAncg0OBU2xvwT4E7am8dbp1u5wEaVZ/5buTOZv8VYVJaAAYKNt+zBMzAaaaKP86YZXndKRTHK/u0zNfew3ChJfN9OFK/gUDf3T12zPd2VyksmGHRHbIM6HiJVHz+1g7Vwnc4Yg7iXNfBiMcFv+WJXoJl1ZJYyxobgoLR7qLLMhShpVhGYmddFySr4uM9aMLnWaygsUIN0WHFwsTtVov3N2Vz3xIOVJs4YiGv2iQLfyZSAI512aDLV7c4xjd9y8P1HlpXF8ccYA9akAuDHulT758KfqtGPbJ8u84czq23Pjv+5qZvH6B59ZkXZlNXbJcQr0mWEw6SjnDcKPiiivm7zYQvIkXN0urlpA8zQOjR4G+ZZ77QW/uf2Khiody8BRUVlIQ8Dl40IrDO0uQublQx55QGe/TX56Q/11m0yXhhojVskGTtgniGpUEYctucEUh4zzNMY2Gl4Ngx2wiM4Q77HSr71Rms5VQScqYWXdV0Ag+3nID18IFwft4GTuW7ls+GRdXXNYhfS1FctWlSg7DLhpXwxkVyVDnhtmlMFvq0ILOEdNASYleYByEWjpIHbcYYbcu1L80uPXVbLLcKyhaNWOOjEa32g+AOEG1dGb/LMQfmWj6MgacDc3HFH/qfh9WWuAEDUTG+iIZswwoOWXXhk0jdbqsl3U3togOHXeybVYl23bJf3VD3yXVYlpZs7NSfyVG6FKUPKxe2flxSzP8R+w0TLh/KQLyrdhLRx9vf2E0WWZ0w/hjPxIwWI3qe5+bF/xneMkvdGjOYk2jOcsIhloilOamIUKZ1FfPGQXfqENRZkmyoLip9Qof8OUzrWNGA3UzsWtBn52GS1jB2FZ40bPYANKebSAyv4pBsDQ+iRWHgBTt0SgILHChlQGJ20oXWjg1t8TzcGMzytF5lMLjwDfhddvC7u/0GowfO/vpbh/x0YJ5aKyOcxxNa3+w+ao/wFS3pPK9egfjHgvukmVtiARqBIdznBZvYUQInVk487D6ELb3KP8TRDnjo5AIPnq/3GObq7fBktisVx/JOZFuFD2CrjHD+Nor1oSx2ofV8G0d0WLq1hd9zxY0GKeiqxYu9u3QO2K750XNz0XGbK+mg1swg44rxtBTbchnC+xbeEZGFEIrwUAMKZT3DnuZ1ylYRCyX+YLcCjYhuWrLzQVE/gYcHrhkbDqG/d+yfaX3tszwra/FG04QInhAQoYsXORaxTsAsWIF6Ymj2FLGYOw0mqYgtq3xt4JOCLL46++Ht2duxOGnEY4gxgO3PYci1qw11mWxih9amBybSCnxiGwOz6+jhjchT9tSI0zQqctJJWXLKjWSG12U4TeNJqaAdwXfgW5WT4TYpwntfrjfMsEHFS3VBsJOlysVeWuTiVirySkCyDIsVZCYcRroG3hZvZChL0D32B5YcceyW6ppjIVBbM1osJoZpF6K7uBI/H4jTNOBt+R07d/umeVqXS8de2YBUEEaRn0QKmG0+1ljcFve/ZzR5SyesCH/axFEuoRRtYj8czw5qmUPVnYQNh+Is3YWehJmlPfF72JvhPTEJcdm2g7PUma0i8z+sDZvh7OktYy8d8YJG+XtNCjywiv3N6sY08GIojuV1YV6dXV5dC5b03cGv4QwXXAWu8anRUWeNg5/0DZprk1ShiDHXuYfZh0kt0J2xLaYu47qgjSYz9SGLemeVw4Rn9oRSZJAB456Dix7kC4khUnad8YlqZ6TisapDRCyu8IHSnHV+SGBh4HjhLJgI6aE7IbQKp1Kwm5v960zRZVnM9Q93yPyNMQ8dsSgsCjHMIaOVzuCMz6Q0/v7k5SvS8PKVuYVe0kwzlOMfgsUE5lr5y25+5XArZ3zLt3AaA4dhkAbJvsUQYRD14Q8XeR4ZlykDzkLydbkF3JYe2VJKsk2qVb6m+i5ZEyUhe8PMrqDPAqiHule7Dd4lAgMwkIH4RHaEKOEiy4GB5aYmd8Sq3C4+JAKSVGtlQnYJ/wZGsKIL8XgZz/IiUvFI0jdk76wGGpF2UOTsYzLreprCccZHVa3qj5ogMGABqo7VuoRHcg3+BF83fWmGlAjksfm/tN+JfJl8t4w/sq6I4WwOAcHzBYmUWXP1v68uzl8E5iccumiVScZSmL4zb7imx0+bpR4Qo4toYRXxg7Pro1MZVr2furFwvRZWh8dpQTQ3xy8x0sV9RvtdJuugRA7CwMm44ABiXMA0FBUXKjoT7PWbd79OkAxy+vpsfH49uXh7fXZxPnl7OX519ivtxnO37W3dfjk+vbgk6+7kB9w7myD++yYs7iCjymooz5UcGCvtVmb5akrfI+K6sIo1/CZy7sG6Iqec3zLnLAG2wp9ArbgfyhnpiLp8Xcvrs/Oxs3CAkC+0a5JwRswP47wsG1OskMie6Ft5GmkAYh1mFk5vT2iGq/EVQq47psNlvWo1Wow84X1OwmJBEougoQbrBDGGAQ8/4PtGHv5aj7/neZxMw0SY6RqT7AOdJyAgsYoNJC3lzBWnFVTCt9lzKiTqblb2eYtF3JL1e5ewumJD3YW6P3mRROH8PAlqeOW9556xW6LhCLU4cG0zN3DYxBmRQ8P5I/Z4IWWKGqF73pWsm3NxxEaGa44QBvHZB5H6VTg1M5Jj4QzhlGNZP0fihOsBrwu4WcLZXZmGROkxybS14FvojArOyq4LcRELSltAcEyIVWv1oqvCVbCbRdOt2kwQuhORDFpTzWlA6xSulaQS64JRhgDlcBu+nbX4EhKC9tWenXCA4YoIsj1InjdS745s4+XZq1fjS8Lo7hnmHzgnpGQ+XdL+25Wq3WszVADxZlpN9bLrPSibAbFUEBuHrhQXBY4r+Lu9v1Xqsn2/h/wGxnvyuwIYbPEPz/1F9zvBfunKlh+c/zm3S65Bdwxd6h/ejQgTwkR29wMwdN/wCuqOS2aey48w1PAV/aUNDYDJ9MflLnx94d20HhXXjcJzfUmTyYNIQkvDh6EKN352zX8rT8l7e4uPs5MvAeMnv+smJwlt/sb11WAFymCI7sp4wmxGQVOIYPSFr7bc5JrVWhGaJAOspFQOreEaaCQOgmwITKTkcCSqKCslo7eYv+zydeXo+W72B8KQddi8FsZPRDOVfFSgIrRbJalDKUTQijwGyKOuVB2MiRLuCRuAZSeF8e2odsMFsQhkmoBiutRizTU2JhNSd+De7iakJHHEjiLO+eFhV2EK9hKzv00Z6HG7qoSFelLmmgjWRAlgzLNFo2I6v6vXNoFAIlRxmg516DzjANfHCoeySZUWPJMQ1Pn7H1b1dPQSWO5yGztqB48zHwn572CSOvrW0FsyVALzDiYp9gr2tYvcuVCFXJTMqoY7OUtgOwCPbc0KYSYiXcX2oEkTmFmXfBSLly6OrGQQbQDyiNE2IGpOKlYv/H4nJMhO/7IiHaqERuJ/Bg17/U03bWcrMiLm83HzwDzrv392E0BOrTeChzinJKvjTy5ohzK0cymcXVZuL2IrZomwndzcN9+Zr7fjlltLwz8c5sC4rJ6+adbYSCenvQ7sx6P241c3nZGemJMpEkQ4pQTHXZHNQSfNZ7clEJ5LmiZRGGflARGKeE4miPgINkaWCBGY2lCRtUA2HP0VM5tzOUEPVr4Gj0Hnxch8w0SuG/n6ZgewOst9DzDdtAD5emvrsPHZK7FDeBqfw0qABQOG7byy2fvcplndZbTyjYFFJWJOF85giMWRtUgzzrFMZkQ2T4kYfyPmWG7tu7OOESkFT73PxIytqMcGD2tgAqNVUaaLlGo5tobi54339JMExQHHXUS1z0DaoKmtMUWfGCCPhKz/D1iwpTjYYgmu+p5xiM7ew/9vcYINI4jP6+91XnHOnjyqXghEYBHuZP2vLqxUhN48MNNalOG1M7AdJnuAAw2SNix1NNK+s0Xs4IDiPU/IaH/E8/D3909vgA8H3oHz2/CZ/bELsM5u3z87pvs2z8MCYu+BtCbop05jC/NY4owkoBrA/UOGuy/AfY8NfuLsb/pBFG8nU7VuGpZjI07IDuB9Lf0tRO3OLXDYNbW7y+15t4KEvutFeZcluPslP7PpUNlHC05qmWxkwBK5f7xjj2VDY/JdPUznoi6q4sFa43OBOacBV0nMTi4ugRD7pNBMCCul2eUpeMfXWHiUnCrsOyQOx9rDKA1X0yg0ZBr7ww79k2jJmpy1a4iHOZ2GpK5ZlWfDLHrcG2AuxKLKS06d0pGtDQjtT1Waji6dafzRmm3q7Ac81Ea8Z203K5H47mVNZLQ1UUH9ouFg+czzaT0eLfBeld6ZKPFJO3eg5zDkA2AN2aqYSLTLkQZV0x9xdQ66OZLMfyUQXsYoOOpqXNajTBNLiDC2Z68ZDzD32Y7Ysp4lP4FT/5AFSAv2j54efTt8+l/Do7+oN/FJz0pBwkSOmtDRs9afuVsSK4ERpGRnEXEvNp8XRV6vbYZmLN72kkt4CAN17DktkV0HHU2fM1OtPSC+llaPkMOFwSxVVRqWXOSZesDVZLRSviUZReIA+/C7OPuUpWpHO0AQ1c/64JwdxTFGrOhZJ4vqfUOINyz3xcGiJANOiu96z43rm4Jnu2bg+oKEk3USKRKMpGYk4C9dQ1IVMQLjHajBvCb28XHgquQY60B8Eu0cyJHN68XSHMJ57+CaxUhJF8YIHEEJ51UsSsx6UYQRDFimskgztlOxAS21IetUKKlcI6Rp6UvMCK2yCMw41YALZ/9n5u3J9Y/y6wCcifUm3QbEjiT9QgHkQCenBvs/5itwr/uDUqx7dsgekuw4XOoVFAkygusM/YEyFoWMAxUk95TMGUVoV0XNQa3GDlOHXChmFcFlWuZpXcW8mMDJwEC+AvukpYBhjvB+YA3FZG7aMw6SMkoWpPS7mTEfIQ49PpzDL8pD+o7clvYhV0DkZRByRMun2wb4+uvk4qf+zoxBukPNLSRZjeTcffV32rXxxe1ML/zqZoQ9voXNFMWNwH1ZpzCS26KmoKgz/723Fp9Pjr9wYY4aN0473c0eV5WbwMPpACNneIRouSaOWIf7+8vxz+fvXr/+rCGTbNeTNt1sdOTkd9LSWQpjnzY5oasr0L6UiLx+R7+0mkOTXuLMedV83JO24KbtESYwWiYloamPJUmNT4sw+G0XxuhguNzbHBwxn19IIjHXauIk0YbXy3DtnjxHBCSpTrYsQz10XBTh99VcUtf+64uLn969nbw6OXv97nJs07YcRrl3Sn+vi82J2+xWM1SfIGbwKTfbCd9ITJwkFDiRLd89xIfzi/PTsYQvNxiw5bB07R/M8lbWIyLcVtgbu98fRDPj+yX62/WNLTnDV1bOzzncbOCEF5RlQ4XjBEUUd8GLrkogFmk1IddPLbaqQquI07DOZqg7EjHNDjNl2K0OFAtQ2K0WPvBNnA6AFBmS6oG5ykUPYIgMT0+duKCIBAkNxmXrPheJjiG58FXqWFoFTd1Jeoyl1S2aul7Jxs1zCTYVWlWkCqNFjXtRHPd5ORFdsRhskcF19BUyqD3bla2AtuWMos5pSUosFNF6N1DlY0H3XFhkG+2ouCiOYYZgHfua4c/gYi5oSVY9VrRl6Z59SIo84zgQ5lKMtbky72+sZKps+REfR140EmsjisU53S25CYwbBiNH4AwEY9Y5olaxnEKwcvDdSkWWJYxrdIZRIreJvi2gCM19HC3iRo1ovLWwgFWn5VQSAggSq4EhTHLCivtaVC7AbF29dKMKo1gPRQkZMynGlS4/OMYC4YLKFlwE3FKlQ5FWOWl0J6VFITmbx86uM8HFcMa+XauA24GcyI8W2HX9yww6TnLUo2a91APbbIU375Nu3GLmWoHxxPwJDwDdve90z5ASLwbfKaxJwvIXXUn0wrOVlNWS6VsK8ZmGiYHrqLzN0tZ/0eh8SOIAcyqSXp9cXZvqPldHW9DruECxcOsCHbR76no+v9q3NSfOBO1poMExdekdD49uOlBybt83ogZwdwgmldSN5jja0uJ1WndW5/6tnODdwo9rsphavH9Ps+p6/j4ZDN+FY+xih9rikQbdbqXfVZ3+ec1rv2bVXXRXy/rXtKS9UFbusx/KbPwKgUimC99P/DG9RyMKdflCfG1G/WElqydY5KEW0dvcJR1eMuySbuhM2DH4ZjN3DN+AmkWS5QkTq2yEedPmQgv7B23dhFA7szfOsyHj5IDMIlIn+o29rCqrbB/6qvmPEdnEIoirDY1W1db/HfhyBJOD/8JgoQVB1A3EBJXUzTz7R1zknOkWaK0JaR6SwMJc2ybWOAbnEyddw6kdgpvLZrH9qUFw4nB3seqBnE+nUwo7n9KR4SBxCtZzw3IO9vS95Dy23qxG0cBPKJdN4ralRtNQglEHSb1DY1P6bDUUb44PeUUTotq2yazkFjUArKpqTpjPIxsaeE+omIuWCNJrjfxeJ+UwjlrHDAexC46esgdaYzdVm+aBHS0y5Me7hsH+4PfnWkA291el4aTKJwlcj0c+ISlpCMhpafV7TWK1SpB4n5oblUA5mlIGjQKkHE47qfRx+r7YJVxz0qbVtAMlZRtAZqL1MIbH8PJ4GIL190R3ONW41fzZe2K9tVpZ0dBfYsl7HSaFZlXtUMUPSlmohOklAYuWrGEoR+AZxNdFn8jbqvdmE88f0xObIjzCLdEZXYVDqn9acIzc42l+dk+ocW9oPfcjdS/NU2pYQIUbtb+K3BEYdzxssihfHuj6x7VFDgqvxTfnoZdGT+qjNenN3T13jdCsUmUMs3z9IPhD5BEuihihmCkXk4kBh2pVUXAkQY5GR+HWTHiVaOl5gdYPl+Pxr+PTyQ/vTi5fTs5P3ow1O20iF8YvvabEEgtgydvCcoCzUmlMa+7atk2yFdfDc023tgRpGB39zgo2u6Rsirztd8D3spdUUb5xYXct27d/3WPNsh2biQ3wmE4s+MCsmlVdAq46abmBChYo7WUkraO10zNwU+VnfDRsC82cHE0nk0E9dvy4dFE4u75yV1OvEfWRGgRvjRRsScfiphvOfThV2IRZY4+xUSflqGvt/aMpNmDigfnZ6Z7jDBSKupvpcE3DGwX4hcZ3O+5D8c/PE2szsgldDmzhszRhYE9rk0vG/KFDsqr8bpARbbmj+nbaFQDDmGRwGHCTdtxG+Pi4m4mwk2fZwvfP9QY6riokGjId8LRwuG9dsWTRf7wkeks/fKxIa7PYtQUBAP4pGDRCsFp2KFphKx27OjR8KWJPLU1Nn2c5cItnbhtCvcXDt60MsxlaXMgH/TFuvcqEp2k0QTe8EUcIfUzZvfJ+64wQK/Se2eLdK61xYVyPpX+dbbtmXT+N31x0KI6UDqzoCdfrYGNKTxiJd8OtL7SM12VgI85Pd2wjwkNPG/p529iSy70fYt8ZZGDed75hohvzJSc/+4AhmSzNkh6vhdPE9g1lZKe0a87zNYoXtlQXie/bdilcpiFRPidPzuZ8HLfqiVzua7B1Q0exhw1hPZFaWbeyNS9c7SVrv5TuBnexCFZstnoPPMooupbzzvg16wEj20tB/rN1wievJu/OkaOq3+FGnVxdX45P3vQ/UZqroBbC3FOXC16/0SmiAzTvi/LYfFEirqJ7i/ufzo+R6WE0+DtzYXYWBXcKg/fCqqPfdLWjjuLU7kLLE6OEJZf2fuS0caCZ2/lNqqatdwZ+PTTz0ppzTqU0p2lYk7V3Sgo6jfo2L6vrPE/flU2tNceyJB881I5cFd2hJqFmlktbsoX2/xLdU9rpqfbJX9CPLVzjzmffmjfJ9wNOstTeZkirRCuEq+uXZ+eT7/96Pb5CWzWnX1ZP2gwwM/wQFgm4RqkOtrzplnmSGe4qBR4g7IulK5Hm8T5NEJ1DucABq5Fkgxmp6HRHEqK7YoXCuJLlL1DGrQnN0BytRLYinsklV0y54ptw1thY6L22XmtiEBfZS054yVpaGEUFRgitJxD9zsSsHrS5ysbYDkqt3qaglyCLuONlLOnsRGOML980CZJnLzGGk19hMzRF+5pLsRSu/5ZPVQTwKBzveHd2PbZY2/RyUjNU2UVzM6mQ7b/mZld/lRqYLV2td0J4+8v45WR8/jOLKmCBejvJcux4pDb2hp+ahdovJIKskcloEbMssBjgb+nYDe7AN1xPUQRJWHJL95E81kxI0Tuh7OWrpKo2spT5Fm63acsuxBCk4wcpVUAyj5vreKJme5ikatxFXsPtlf5/x3zHQFzN8+EMA+7hlZltcIGH60V65I9eh25oS9YzLWEQS+XSkIPtSXbMQfmQHgz8lec8Of9r49cW/wf88r0nNjakhBHlGgtaw1hHQk5pmVU+r5BWkDkOeC4MdCqNxftVmvHFK+Nz1fSsSNYVO78QlluGBahtwKV7+aKwlX/SZw4mDOpG2btlSybDyLcdObiXkW1ZByrjCnyHIjmJ/QFemU6/QWDELTsjOb+euSytpjykm9YPE3wO1uIEWuUr8fknqAyDW4/sxJz4OvA8TIOecLjTi/Ord2/Ozn+gT2/enJy/FESXRl3DkHhpNVzm+Z03aAqkw6wqJwxLUW4axP1lGSv+dYzBg6YeiIHgNhZkxJODbqpLIDxtRVHCVQ4fOtq6vehmA3pD71PJbG3RRDP0Pgj0dlTii2IdRrLxiW7All42IGB5eGC7JDrt6UQCcK9cdg6cuwYwAGwUZndxU9fXNnux5NDUOjRdps3WSd02eZ+iDJ9kwvEItdDrxjHSJTTF6I6c+CJEQvzx3mHRGiRiL7I2zJFInIPQNcE8ZexjDy+zICKgwLzLADsteVcilKibqJbPXbvWlMlqrSkv2tjJdq1zDNiZtGiRNB375COH+pyWE7vIuxHe2rAJNyqOc9sxJOg2pvjfNQA7i9BupyO0dKMpi6YfgSdXvIFtH9A8wr1WR/pkwBxnQ5fp//vmKSb5pDmKm5RqJM9CnmgtAhuzeiShwk7qPLTl1KPLO73+neBV96g6jX9o7L/VR0+f/Rd31ovcjDbtwOwU73V1jTYP09uVvuM59Sei+DpzsfTVJrNOSmQOugnM21rTOjVnbM8E0h6d9GE0IUYDIscYIRbzyK63dmaj4GX4sHeX3f3sXpJExT9vm50FK9ocdfp47XQaw9ctCT7HylqLZLGsOvl6sqk2PLFs8jzdzBtp/2yTQvx1yl1SpcAWnAnt9s/advtWCPdtbN3mjDZJtMTsJTmgRWrH7d4mhsKJhN9tsHgz3mnTelq3WeeJ9mBbyrCd934XU/q4+8TAxguOd87FmUMSW/2j46nbZcB3EEk7XLO3SLuS73zRgfHtngAJ1jr7exBgd8vOfyEQsBEM2N2+UU9gnxNcPXHhtORLkwk8cpNJ341Rb5VKbXsmBEE0bhTbUtwcHXwKdWFbv4xGdp+3rjDdrGSkijEU7BhdLHGRl8gaYb+vNKt9aFvjWrW2GZ0OiRSD4PNdDXJYjocR/jMoae+fHd/sh0tL16730JyyRQ+fdWltMXj/HDsGd3a83juX+i/ghwrBn+KHaR4WESi9KOp1tSXbnn319PHI0qZEkVBl2HJR/4uyLw3imkXsYX2fEYnado45kad2UXYktNUShdi+oQGit9vRTbtUks2JqsxmiLYl/bHZ7DXfpkc0rEWW0f4OpKCfO/jRXp3dR7jodiVzrmKBO7gVTG1NAmnvFY3MDmb1M3cq2jpdZgi0vwIU9Cu/s6L9laajH3fZ6A5my/1/2O6+rqvLdVjDUQUnA3udjiUqdaqaqqQ2xp2ADoigzIUYeDQrtMQoFuXfxsVZueY0S3nniujhhRSfNAkVrrHmHkTf7RPlGDTMC7etHGnhkmRdztp5cC+LZbx67/Hd7IeX91QE02+/1ibUnYHaqqawnCWJIn1XIGw2zGZgDaTCKqpX69LnSfu7fO0bntku7bZKCnG+Ch5aIdt95PpP8ZCm5x7yBaS/PPTM0s1bJKEwA02nz+HZrPLC5riSJh0it8p20OaEnTa5RqpydNC7BImaTiYIJAdCWIpBJIBFzEhQf1kzOhVtk9C2PTfyUTjXsc4Suzn0f7edP+dtv3Yf/2c1GShyNi6KcffvQP7z9Zt0jB+Y9uvk5avX/V0bgn+ZDIrUxT7blPt4q1a2aSxvc1ykjKepHoaY8W1b/L5t2D4cGm5ohAvSg2y4MTK7iGxL+G5XrACvO5H+WVDGOYCsBKkd4CU3It8alERpVuE9ME7Hee5bhyankDY+vwiHAa85o8N5KhovQ5mmvkvwYpNNQChAWUNmVLK5NqF9G48DIq1t1qLPpns7qj+DHYbu/gjJE6eBK0fb2T+dxnOwQzIlimr3SzGaNwUsuZ2wqM3P5WUXGxMkVePtl40cyHEgua1Jb9GXOkjVTsfT15nWb1PW3W5d3LjQVrVxCzXr1DgolUCd1yt0Y/hhSsy6H/wTLV138jTZ2j/R97X3SUprSLXfU+6VoJQcpdtaFl2G9xPOOxs5Tdu0I5/7k+wd/f7ahXRbx9pOvk7zbpd6pYH1liYl08Xh3fa9ZNLLy2yON/VtiB2na2PTj3Ozc2N3Et1T07Nw/xLidGMR48vLz1sEJ779/1gEXtmzEZlsT25rtJ2xxHz6W7co2frY9hYVO2p82wLPHrctS/tA6B9xzzOOP6uTjyaDE15axoU7RuRmUiQ8pnFxKA2aDrM6TfvHBopfo9ygR+JGH+CtwVyshliiuUV5xG+kPD7t9zcyt+gOLWsW3+zTXbHVTi319cN6Zwn1bqrqnqhVzeT0u80vN7sA2q5obitQp2Wrv6cXJt6htNndkL26TTf7ufbAvNXeiG3z1sC8SURP2mjQihcQSrNRd83iKNvWXzjNlfSQ5i03quMOJDOJUfXZ0V++1CH9Z185LHM77v5vc8dPhPQ3DN3PHs6qd18/2+O46Az9eNaHWx2g1OxCml/TJdHKqmhajjW1PfqmupAzazVDVV82BokpCd42CuhUTfALFMX7R9/XaVzFbVamb8tp0C5pwIolSdDf8ulAOrM6Z7ZPke526dUpEFve7/9rykWVkNSRPGGJPENjy0ibW060Y63tZqkv2ONfEZR33/1oopq1aTf8i9Jm0BC/uGpn52Md2Gl2uU1DfXa7KN0JJ+QVmGWibeRIHxy6jW1ZS7TaO9Q+SeAnmlnTIokBGG/MuMI6hfagIsUsCAKz0VTXM8CG2MlVx5kv7AsLtMrR6nliPkSq5aI6WlrmchgZO5AmM4QseJvXK94FezIULLQRm9KvGpY1UOK2w/o6x+ubuFSa40WHUfyB2XnzNiAFu4JJ3qYp+lZgAX4V66sbEOkiKNjW0aqe6klH+awM+k3g0EZtMtPRA1px3H+s774EeDabIO9tZvx4i9L9grckG3V9BH8CwsP4n+AD8LD37GLyy+XF+eu/9gfNgrb6xn8ihjPYkJH9PQlBvR7sKO7NN5lwzGQyAb5MJhoy6axfRZog1Gdav5Bp1oaTc8vCArUKhDaEAJYrKJKyQIbpCtTZeKEYzCApKtWqVWtssGVTmsZ8tB5OqXUrxdydhTUspq2VBmYMQRQKyjeePkdshpKPM2ysX35dp+RMOi+ehNdBGmQ01CjxBdpRReT8LNiEo53rEa7Ws+1zQZg+nuv3/h+m79tXe3gAAA==" "${HOME}/.iterm2/it2.f1f13ef87d320f31.py" || return 1
    fi
    command python3 "${HOME}/.iterm2/it2.f1f13ef87d320f31.py" "$@"
  }
fi
