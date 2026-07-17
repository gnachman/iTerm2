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
      if ( ! ($?iterm2_hostname)) then
          alias _iterm2_print_remote_host 'printf "1337;RemoteHost=%s@%s" "$USER" `hostname -f`'
      else
          alias _iterm2_print_remote_host 'printf "1337;RemoteHost=%s@%s" "$USER" "$iterm2_hostname"'
      endif
      alias _iterm2_remote_host "(_iterm2_start; _iterm2_print_remote_host; _iterm2_end)"

      # Define aliases for printing the current directory
      alias _iterm2_print_current_dir 'printf "1337;CurrentDir=$PWD"'
      alias _iterm2_current_dir "(_iterm2_start; _iterm2_print_current_dir; _iterm2_end)"

      # Define aliases for printing the shell integration version this script is written against
      alias _iterm2_print_shell_integration_version 'printf "1337;ShellIntegrationVersion=8;shell=tcsh"'
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
      alias _iterm2_update_current_state '_iterm2_remote_host; _iterm2_current_dir; _iterm2_user_defined_vars'

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
    if ( ! -f "$HOME/.iterm2/it2.4a5c7f87cc6e339b.py" ) then
      python3 -c 'import base64,glob,gzip,os,sys,tempfile; d=os.path.expanduser("~/.iterm2"); os.makedirs(d,exist_ok=True); data=gzip.decompress(base64.b64decode(sys.argv[1])); fd,tmp=tempfile.mkstemp(dir=d); os.write(fd,data); os.close(fd); os.replace(tmp,sys.argv[2]); [os.remove(f) for f in glob.glob(os.path.join(d,"it2*.py")) if f!=sys.argv[2]]' "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" "$HOME/.iterm2/it2.4a5c7f87cc6e339b.py"
    endif
    alias it2 'python3 "$HOME/.iterm2/it2.4a5c7f87cc6e339b.py" \!*'
  else
    # Diagnostic to stderr with a non-zero exit, matching the other shells, so callers
    # like `set x = \`it2 ...\`` do not capture it as output and see success.
    alias it2 'sh -c "echo it2: python3 is required >&2; exit 1"'
  endif
endif
