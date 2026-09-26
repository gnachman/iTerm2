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

    if ( x"$ITERM_ENABLE_SHELL_INTEGRATION_WITH_TMUX""$TERM" != xscreen && x"$ITERM_ENABLE_SHELL_INTEGRATION_WITH_TMUX""$TERM" != xtmux-256color && x"$TERM" != xlinux && x"$TERM" != xdumb ) then


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
          alias _iterm2_print_osc7 'printf "7;file://%s@%s%s%s" "$_iterm2_user" "`hostname -f`" `printf "%s" "$PWD" | env LC_ALL=C awk "$_iterm2_urlencode_awk"` "$_iterm2_machine_id_query"'
      else
          alias _iterm2_print_osc7 'printf "7;file://%s@%s%s%s" "$_iterm2_user" "$_iterm2_hostname" `printf "%s" "$PWD" | env LC_ALL=C awk "$_iterm2_urlencode_awk"` "$_iterm2_machine_id_query"'
      endif
      alias _iterm2_osc7 "(_iterm2_start; _iterm2_print_osc7; _iterm2_end)"

      # Define aliases for printing the shell integration version this script is written against
      alias _iterm2_print_shell_integration_version 'printf "1337;ShellIntegrationVersion=9;shell=tcsh"'
      alias _iterm2_shell_integration_version "(_iterm2_start; _iterm2_print_shell_integration_version; _iterm2_end)"

      # Define aliases for defining the boundary between a command prompt and the
      # output of a command started from that prompt. $_iterm2_current_aid is
      # constant per shell session (see note above) so every C/A/B/D in this
      # shell carries the same aid string.
      if (! $?TERM_PROGRAM) then
          alias _iterm2_print_between_prompt_and_exec 'printf "133;C;aid=$_iterm2_current_aid"'
      else
        if ( x"$TERM_PROGRAM" != x"iTerm.app" ) then
          alias _iterm2_print_between_prompt_and_exec 'printf "133;C;aid=$_iterm2_current_aid"'
        else
          alias _iterm2_print_between_prompt_and_exec 'printf "133;C;aid=$_iterm2_current_aid\r"'
        endif
      endif

      alias _iterm2_between_prompt_and_exec "(_iterm2_start; _iterm2_print_between_prompt_and_exec; _iterm2_end)"

      # Define aliases for defining the start of a command prompt.
      alias _iterm2_print_before_prompt 'printf "133;A;aid=$_iterm2_current_aid"'
      alias _iterm2_before_prompt "(_iterm2_start; _iterm2_print_before_prompt; _iterm2_end_prompt)"

      # Define aliases for defining the end of a command prompt.
      alias _iterm2_print_after_prompt 'printf "133;B;aid=$_iterm2_current_aid"'
      alias _iterm2_after_prompt "(_iterm2_start; _iterm2_print_after_prompt; _iterm2_end_prompt)"

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

      # Define precmd, which runs just before the prompt is printed. This could go
      # in $prompt but this keeps things a little simpler in here.
      # No parens or iterm2_start call is allowed prior to evaluating the last status.
      alias precmd '_iterm2_last_status; _iterm2_update_current_state'

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

      # Turn globbing back on.
      unset noglob
    endif
  endif
endif

# it2 CLI over iTerm2 SSH integration: materialize the embedded copy (named by
# content hash, so a shipped update replaces a stale one) and alias it2 unless it
# already exists (tcsh's which builtin also reports aliases). Without python3, alias
# it2 to a clear message rather than a bare, failing python3 call.
which it2 >& /dev/null
if ( $status != 0 ) then
  which python3 >& /dev/null
  if ( $status == 0 ) then
    if ( ! -f "$HOME/.iterm2/it2.2e1a7f98b497171c.py" ) then
      python3 -c 'import base64,glob,gzip,os,sys,tempfile; d=os.path.expanduser("~/.iterm2"); os.makedirs(d,exist_ok=True); data=gzip.decompress(base64.b64decode(sys.argv[1])); fd,tmp=tempfile.mkstemp(dir=d); os.write(fd,data); os.close(fd); os.replace(tmp,sys.argv[2]); [os.remove(f) for f in glob.glob(os.path.join(d,"it2*.py")) if f!=sys.argv[2]]' "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" "$HOME/.iterm2/it2.2e1a7f98b497171c.py"
    endif
    alias it2 'python3 "$HOME/.iterm2/it2.2e1a7f98b497171c.py" \!*'
  else
    # Diagnostic to stderr with a non-zero exit, matching the other shells, so callers
    # like `set x = \`it2 ...\`` do not capture it as output and see success.
    alias it2 'sh -c "echo it2: python3 is required >&2; exit 1"'
  endif
endif
