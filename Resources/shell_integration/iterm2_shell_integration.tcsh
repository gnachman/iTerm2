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
    if ( ! -f "$HOME/.iterm2/it2.212690748889c7bb.py" ) then
      python3 -c 'import base64,glob,gzip,os,sys,tempfile; d=os.path.expanduser("~/.iterm2"); os.makedirs(d,exist_ok=True); data=gzip.decompress(base64.b64decode(sys.argv[1])); fd,tmp=tempfile.mkstemp(dir=d); os.write(fd,data); os.close(fd); os.replace(tmp,sys.argv[2]); [os.remove(f) for f in glob.glob(os.path.join(d,"it2*.py")) if f!=sys.argv[2]]' "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" "$HOME/.iterm2/it2.212690748889c7bb.py"
    endif
    alias it2 'python3 "$HOME/.iterm2/it2.212690748889c7bb.py" \!*'
  else
    # Diagnostic to stderr with a non-zero exit, matching the other shells, so callers
    # like `set x = \`it2 ...\`` do not capture it as output and see success.
    alias it2 'sh -c "echo it2: python3 is required >&2; exit 1"'
  endif
endif
