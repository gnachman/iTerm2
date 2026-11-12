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

# Note that tcsh doesn't allow the prompt to end in an escape code so the terminal space here is required. iTerm2 ignores spaces after this code.
# This is the second version of this script. It rejects "screen" terminals and uses aliases to make the code readable.

# Prevent the script from running twice.
if ( ! ($?iterm2_shell_integration_installed)) then
  # Make sure this is an interactive shell.
  if ($?prompt) then

    # Define aliases for the start and end of OSC escape codes used by shell integration.
    if ( ! ($?ITERM_ENABLE_SHELL_INTEGRATION_WITH_TMUX)) then
      setenv ITERM_ENABLE_SHELL_INTEGRATION_WITH_TMUX ""
    endif

    # Inside tmux (TERM=tmux*, or $TMUX set when tmux uses a screen* TERM), tmux Integration passes
    # the escape codes on intact and plain tmux discards them, so this loads; TERM=tmux* also
    # reaches a host sshed to from a tmux pane. So does TERM=screen-256color, which many tmux users
    # set. Other screen* TERMs without $TMUX are screen, or tmux beyond an ssh hop, and are skipped. ITERM_ENABLE_SHELL_INTEGRATION_WITH_TMUX forces it on.
    set _iterm2_in_tmux = 0
    if ( $?TMUX ) then
      if ( "$TMUX" != "" ) set _iterm2_in_tmux = 1
    endif
    if ( ( x"$ITERM_ENABLE_SHELL_INTEGRATION_WITH_TMUX" != x || $_iterm2_in_tmux || "$TERM" !~ screen* || x"$TERM" == xscreen-256color ) && x"$TERM" != xlinux && x"$TERM" != xdumb ) then


      set iterm2_shell_integration_installed="yes"

      # OSC 133 aid: per-SHELL identifier the receiver uses to target a
      # specific mark for D-by-aid (and cascade-close when an outer
      # command like ssh dies before its inner remote shell's D arrives).
      #
      # tcsh limitation: unlike bash/zsh/fish, tcsh's `set prompt=...`
      # captures the A/B sequences at script-source time via backticks
      # rather than re-evaluating per prompt. We can't make the aid
      # change per-command without restructuring the prompt mechanism,
      # so the aid is constant per shell session. That still
      # disambiguates local vs remote shells in nested ssh (PIDs and
      # start times differ between the outer and inner shells), which
      # is the main use case, but D-by-aid within one tcsh session
      # always targets the most-recently created mark, equivalent to
      # today's topmost-open behavior. tcsh has no $RANDOM/$random; $$
      # (PID) plus `date +%s` (POSIX-standard since 2001, supported on
      # macOS / Linux / *BSD / AIX 5.3+ / Solaris 10+) is the most
      # portable per-shell identifier available at source time.
      set _iterm2_current_aid = "tcsh-$$-`date +%s`"

      alias _iterm2_start 'printf "\033]"'
      alias _iterm2_end 'printf "\007"'
      alias _iterm2_end_prompt 'printf "\007"'

      # Define aliases for printing the current hostname
      # If hostname -f is slow to run on your system, set iterm2_hostname before sourcing this script.
      if ( ! ($?iterm2_hostname)) then
          # hostname is fast on macOS so don't cache it. This lets us have an up to date value if it
          # changes because you connect to a VPN, for example.
          if ( `uname` != Darwin ) then
              set iterm2_hostname=`hostname -f |& cat || false`
              # some flavors of BSD (i.e. NetBSD and OpenBSD) don't have the -f option
              if ( $status != 0 ) then
                  set iterm2_hostname=`hostname`
              endif
          endif
      endif
      # OSC 7: report username, hostname, and working directory as a single file
      # URL, superseding the older 1337;RemoteHost and 1337;CurrentDir codes. The
      # path is percent-encoded byte-wise by awk (LC_ALL=C) so UTF-8 survives. The
      # awk program is stored in a variable to keep the alias quoting manageable.
      # awk splits input on newlines (RS), so a path containing a newline arrives as
      # multiple records; emit the encoded newline (%0A) between them so it is not
      # silently dropped.
      set _iterm2_urlencode_awk = 'BEGIN{for(i=0;i<256;i++)ord[sprintf("%c",i)]=i}{if(NR>1)printf "%%0A";s=$0;for(i=1;i<=length(s);i++){c=substr(s,i,1);if(c~/[\/._~A-Za-z0-9-]/)printf "%s",c;else printf "%%%02X",ord[c]}}'

      # Machine identity for localhost detection (see the OSC 7 machineID design).
      # Version 1 is HMAC-SHA256(fixed key, macOS kern.bootsessionuuid) as hex; the
      # receiver HMACs its own the same way and compares, so it knows the shell
      # shares its filesystem without matching hostnames. We HMAC rather than send
      # the raw per-boot UUID. This is a `set` (not `setenv`) variable, so it never
      # enters the environment and cannot leak across ssh. A non-Darwin host reports
      # "1:" (not this Mac); a Darwin failure reports "0:" (identity unavailable ->
      # hostname fallback).
      if ( ! ($?_iterm2_machine_id) ) then
          if ( `uname` == Darwin ) then
              set _iterm2_bsid = `sysctl -n kern.bootsessionuuid`
              set _iterm2_machine_id = "0:"
              if ( "$_iterm2_bsid" != "" ) then
                  set _iterm2_hmac = `printf "%s" "$_iterm2_bsid" | /usr/bin/openssl dgst -sha256 -hmac "iterm2-osc7-machine-id" | awk '{print $NF}'`
                  if ( "$_iterm2_hmac" != "" ) set _iterm2_machine_id = "1:$_iterm2_hmac"
                  unset _iterm2_hmac
              endif
              unset _iterm2_bsid
          else
              set _iterm2_machine_id = "1:"
          endif
      endif
      set _iterm2_machine_id_query = "?machineID=$_iterm2_machine_id"

      # Sanitize the authority: a username or hostname with a URL-structural
      # character (/, ?, #, or whitespace) would silently restructure the URL -
      # recording the wrong directory, or (since the machineID query still parses)
      # poisoning localhost detection with a truncated host. Keep only a safe set so
      # a malformed label degrades to a clean name; the username keeps @ (an AD login
      # like alice@corp.com survives, since URL parsers split on the LAST @).
      # (`hostname -f`, used when iterm2_hostname is unset, is already clean.)
      # Sanitize into script-private variables, NOT the user's iterm2_hostname: every
      # other shell copies into a local and leaves the user's variable intact. The
      # alias expands its variables at emission time, so it must read the sanitized
      # private copy (_iterm2_hostname) rather than $iterm2_hostname - otherwise a
      # value assigned after sourcing would never go through the sed, reopening the
      # URL-restructuring hole.
      set _iterm2_user = `printf "%s" "$USER" | sed 's/[^A-Za-z0-9._@-]//g'`
      if ( $?iterm2_hostname ) then
          set _iterm2_hostname = `printf "%s" "$iterm2_hostname" | sed 's/[^A-Za-z0-9._-]//g'`
      endif

      if ( ! ($?iterm2_hostname)) then
          # Quote the hostname substitution so its output is one argument. An
          # unquoted backtick word-splits: a hostname containing whitespace would
          # then fill several %s and push the trailing ?machineID= argument off the
          # end (silently dropped), and the positions would misalign.
          alias _iterm2_osc7 'printf "\033]7;file://%s@%s%s%s\007" "$_iterm2_user" "`hostname -f`" `printf "%s" "$PWD" | env LC_ALL=C awk "$_iterm2_urlencode_awk"` "$_iterm2_machine_id_query"'
      else
          alias _iterm2_osc7 'printf "\033]7;file://%s@%s%s%s\007" "$_iterm2_user" "$_iterm2_hostname" `printf "%s" "$PWD" | env LC_ALL=C awk "$_iterm2_urlencode_awk"` "$_iterm2_machine_id_query"'
      endif

      # Define aliases for printing the shell integration version this script is written against
      alias _iterm2_shell_integration_version 'printf "\033]1337;ShellIntegrationVersion=13;shell=tcsh\007"'

      # Define aliases for defining the boundary between a command prompt and the
      # output of a command started from that prompt. $_iterm2_current_aid is
      # constant per shell session (see note above) so every C/A/B/D in this
      # shell carries the same aid string.
      if (! $?TERM_PROGRAM) then
          alias _iterm2_between_prompt_and_exec 'printf "\033]133;C;aid=$_iterm2_current_aid\007"'
      else
        if ( x"$TERM_PROGRAM" != x"iTerm.app" ) then
          alias _iterm2_between_prompt_and_exec 'printf "\033]133;C;aid=$_iterm2_current_aid\007"'
        else
          alias _iterm2_between_prompt_and_exec 'printf "\033]133;C;aid=$_iterm2_current_aid\r\007"'
        endif
      endif


      # Define aliases for defining the start of a command prompt.
      alias _iterm2_before_prompt 'printf "\033]133;A;aid=$_iterm2_current_aid\007"'

      # Define aliases for defining the end of a command prompt.
      alias _iterm2_after_prompt 'printf "\033]133;B;aid=$_iterm2_current_aid\007"'

      # Define aliases for defining the start of a right prompt (Semantic Prompt
      # k=r). The receiver records the right prompt's cells as an excluded
      # subrange on the active primary mark, so they aren't saved as part of the
      # command. tcsh pads the gap before rprompt with spaces, so nothing else
      # can tell the right prompt apart from the command.
      alias _iterm2_before_right_prompt 'printf "\033]133;P;k=r;aid=$_iterm2_current_aid\007"'

      # Define aliases for printing the status of the last command.
      alias _iterm2_last_status 'printf "\033]133;D;$?;aid=$_iterm2_current_aid\007"'

      # Usage: iterm2_set_user_var key `printf "%s" value | base64`
      alias iterm2_set_user_var 'printf "\033]1337;SetUserVar=%s=%s\007"'

      # User may override this to set user-defined vars. It should look like this, because your shell is terrible for scripting:
      # alias _iterm2_user_defined_vars (iterm2_set_user_var key1 `printf "%s" value1 | base64`; iterm2_set_user_var key2 `printf "%s" value2 | base64`; ...)
      (which _iterm2_user_defined_vars >& /dev/null) || alias _iterm2_user_defined_vars ''

      # Combines all status update aliases
      alias _iterm2_update_current_state '_iterm2_osc7; _iterm2_user_defined_vars'

      # This is necessary so the first command line will have a hostname and current directory.
      _iterm2_update_current_state
      _iterm2_shell_integration_version

      # Install Shell Integration & Utilities used to alias it2ssh to a copy in .iterm2, which
      # hides the newer it2ssh iTerm2 puts on PATH. Remove that alias, and only that alias, when
      # the it2ssh PATH finds first is the one inside iTerm2's app bundle. Done at the first
      # prompt because the installer appended the alias after this script, and then the alias
      # empties itself. sh makes the whole decision because tcsh substitutes variables in an
      # alias before any of its commands run, and because tcsh's own which reports the alias
      # rather than searching PATH.
      alias _iterm2_drop_stale_it2ssh_alias 'if ({ sh -c '\''case "$1" in */.iterm2/it2ssh) p=$(command -v it2ssh) || exit 1; case "$p" in */Contents/Resources/utilities/it2ssh) exit 0;; esac;; esac; exit 1'\'' sh "`alias it2ssh`" }) unalias it2ssh; alias _iterm2_drop_stale_it2ssh_alias '\'\'''

      # Define precmd, which runs just before the prompt is printed. This could go
      # in $prompt but this keeps things a little simpler in here.
      # No parens or iterm2_start call is allowed prior to evaluating the last status.
      alias precmd '_iterm2_last_status; _iterm2_update_current_state; _iterm2_drop_stale_it2ssh_alias'

      # Define postcmd, which runs just before a command is executed.
      alias postcmd '(_iterm2_between_prompt_and_exec)'

      # Quotes are ignored inside backticks, so use noglob to prevent bug 3393.
      set noglob

      # Remove the terminal space from the prompt to work around a tcsh bug.
      # Set the echo_style so Centos (and perhaps others) will handle multi-
      # line prompts correctly.
      set _iterm2_saved_echo_style=$echo_style
      set echo_style=bsd
      set _iterm2_truncated_prompt=`echo "$prompt" | sed -e 's/ $//'`
      set echo_style=$_iterm2_saved_echo_style
      unset _iterm2_saved_echo_style

      # Wrap the prompt in FinalTerm escape codes and re-add a terminal space.
      set prompt="%{"`_iterm2_before_prompt`"%}$_iterm2_truncated_prompt%{"`_iterm2_after_prompt`"%} "

      # Wrap the right prompt the same way. tcsh draws a %{...%} sequence
      # together with the character after it and drops one at the very end
      # ("we lose the last literal, if it is not followed by a normal
      # character", ed.refresh.c), so the closing B needs a visible character
      # after it. That trailing space moves the right prompt one column left;
      # there's no way to close the mark without one. The value is substituted
      # inside double quotes rather than run through a subshell, which would
      # collapse runs of spaces in it. Skip a right prompt that already
      # contains a 133;P mark, since a second, nested mark would confuse the
      # receiver. ITERM2_SQUELCH_RPROMPT_MARK opts out.
      if ($?rprompt && ! $?ITERM2_SQUELCH_RPROMPT_MARK) then
        if ( "$rprompt" != "" && "$rprompt" !~ *133\;P* ) then
          set rprompt="%{"`_iterm2_before_right_prompt`"%}$rprompt%{"`_iterm2_after_prompt`"%} "
        endif
      endif

      # Turn globbing back on.
      unset noglob
    endif
  endif
endif

# Put iTerm2's uploaded it2 on PATH, ahead of the shell function below. Exported, so a program
# started from this shell passes it on: a Claude Code hook runs through `sh -c` and an agent's
# Bash tool does too, and neither sees a shell function. Done here rather than from the app
# because the real PATH is only known in the login shell; the conductor cannot express a prepend
# (its setenv does no re-expansion) and an absolute value there would break conductor.sh itself.
# Guarded on the directory existing, so a host iTerm2 never uploaded to keeps a clean PATH. Moved
# to the front if it is already on PATH, so iTerm2's it2 wins over any other (a login profile's
# path_helper or a `brew shellenv` may have put other directories ahead of it), and never
# duplicated, so re-sourcing does not stack copies.
if ( -d "$HOME/.iterm2/bin" ) then
  set _iterm2_rest = ( )
  foreach _iterm2_dir ( $path:q )
    if ( "$_iterm2_dir" != "$HOME/.iterm2/bin" ) set _iterm2_rest = ( $_iterm2_rest:q "$_iterm2_dir" )
  end
  set path = ( "$HOME/.iterm2/bin" $_iterm2_rest:q )
  unset _iterm2_rest _iterm2_dir
endif

# it2 CLI over iTerm2 SSH integration: materialize the embedded copy (named by
# content hash, so a shipped update replaces a stale one) and alias it2 unless it
# already exists (tcsh's which builtin also reports aliases). Without python3, alias
# it2 to a clear message rather than a bare, failing python3 call.
which it2 >& /dev/null
if ( $status != 0 ) then
  which python3 >& /dev/null
  if ( $status == 0 ) then
    if ( ! -f "$HOME/.iterm2/it2.360a8dc76dd1793c.py" ) then
      python3 -c 'import base64,gzip,os,sys,tempfile; d=os.path.expanduser("~/.iterm2"); os.makedirs(d,exist_ok=True); data=gzip.decompress(base64.b64decode(sys.argv[1])); fd,tmp=tempfile.mkstemp(dir=d); os.write(fd,data); os.close(fd); os.replace(tmp,sys.argv[2])' "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" "$HOME/.iterm2/it2.360a8dc76dd1793c.py"
    endif
    alias it2 'python3 "$HOME/.iterm2/it2.360a8dc76dd1793c.py" \!*'
  else
    # Diagnostic to stderr with a non-zero exit, matching the other shells, so callers
    # like `set x = \`it2 ...\`` do not capture it as output and see success.
    alias it2 'sh -c "echo it2: python3 is required >&2; exit 1"'
  endif
endif
