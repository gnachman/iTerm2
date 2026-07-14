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
    if ( ! -f "$HOME/.iterm2/it2.e86e52cd6f0ff62a.py" ) then
      python3 -c 'import base64,glob,gzip,os,sys,tempfile; d=os.path.expanduser("~/.iterm2"); os.makedirs(d,exist_ok=True); data=gzip.decompress(base64.b64decode(sys.argv[1])); fd,tmp=tempfile.mkstemp(dir=d); os.write(fd,data); os.close(fd); os.replace(tmp,sys.argv[2]); [os.remove(f) for f in glob.glob(os.path.join(d,"it2*.py")) if f!=sys.argv[2]]' "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" "$HOME/.iterm2/it2.e86e52cd6f0ff62a.py"
    endif
    alias it2 'python3 "$HOME/.iterm2/it2.e86e52cd6f0ff62a.py" \!*'
  else
    alias it2 'echo "it2: python3 is required"'
  endif
endif
