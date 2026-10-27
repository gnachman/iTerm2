#!/bin/bash
# The iTerm2 customizations fall under the following license:
#
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


# -- BEGIN ITERM2 CUSTOMIZATIONS --
# Inside tmux (TERM=tmux*, or $TMUX set when tmux uses a screen* TERM), tmux Integration passes the
# escape codes on intact and plain tmux discards them, so this loads; TERM=tmux* also reaches a host
# sshed to from a tmux pane. So does TERM=screen-256color, which many tmux users set. Other screen*
# TERMs without $TMUX are screen, or tmux beyond an ssh hop, and are skipped. ITERM_ENABLE_SHELL_INTEGRATION_WITH_TMUX forces it on.
if [[ ( -n "$ITERM_ENABLE_SHELL_INTEGRATION_WITH_TMUX" || -n "$TMUX" || "$TERM" != screen* || "$TERM" = screen-256color ) && "$ITERM_SHELL_INTEGRATION_INSTALLED" = "" && "$-" == *i* && "$TERM" != linux && "$TERM" != dumb ]]; then

if shopt extdebug | grep on > /dev/null; then
  echo "iTerm2 Shell Integration not installed."
  echo ""
  echo "Your shell has 'extdebug' turned on."
  echo "This is incompatible with shell integration."
  echo "Find 'shopt -s extdebug' in bash's rc scripts and remove it."
  return 0
fi

ITERM_SHELL_INTEGRATION_INSTALLED=Yes
# Saved copy of your PS1. This is used to detect if the user changes PS1
# directly. ITERM_PREV_PS1 will hold the last value that this script set PS1 to
# (including various custom escape sequences).
ITERM_PREV_PS1="$PS1"

# A note on execution. When you invoke a command at an interactive prompt the following steps are taken:
#
# 1. The DEBUG trap runs.
#   It calls __bp_preexec_invoke_exec
#     It runs any registered preexec_functions, including __iterm2_preexec
# 2. The command you executed runs.
# 3. PROMPT_COMMAND runs.
#   It runs __bp_precmd_invoke_cmd, which is inserted as the first command in PROMPT_COMMAND.
#     It calls any registered precmd_functions
#   Then, pre-existing PROMPT_COMMANDs run
# 4. The prompt is shown.
#
# __iterm2_prompt_command used to be run from precmd_functions but then a pre-existing
# PROMPT_COMMAND could clobber the PS1 it modifies. Instead, add __iterm2_prompt_command as the last
# of the "preexisting" PROMPT_COMMANDs so it will be the very last thing done before the prompt is
# shown (unless someone amends PROMPT_COMMAND, but that is on them).
if [[ -n "$PROMPT_COMMAND" ]]; then
    PROMPT_COMMAND+=$'\n'
fi;
PROMPT_COMMAND+='__iterm2_prompt_command'

# The following chunk of code, bash-preexec.sh, is licensed like this:
# The MIT License
#
# Copyright (c) 2015 Ryan Caloras and contributors (see https://github.com/rcaloras/bash-preexec)
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.

# Wrap bash-preexec.sh in a function so that, if it exits early due to having
# been sourced elsewhere, it doesn't exit our entire script.
_install_bash_preexec () {
# -- END ITERM2 CUSTOMIZATIONS --

# -- BEGIN BASH-PREEXEC.SH --
# bash-preexec.sh -- Bash support for ZSH-like 'preexec' and 'precmd' functions.
# https://github.com/rcaloras/bash-preexec
#
#
# 'preexec' functions are executed before each interactive command is
# executed, with the interactive command as its argument. The 'precmd'
# function is executed before each prompt is displayed.
#
# Author: Ryan Caloras (ryan@bashhub.com)
# Forked from Original Author: Glyph Lefkowitz
#
# V0.6.0
#

# General Usage:
#
#  1. Source this file at the end of your bash profile so as not to interfere
#     with anything else that's using PROMPT_COMMAND.
#
#  2. Add any precmd or preexec functions by appending them to their arrays:
#       e.g.
#       precmd_functions+=(my_precmd_function)
#       precmd_functions+=(some_other_precmd_function)
#
#       preexec_functions+=(my_preexec_function)
#
#  3. Consider changing anything using the DEBUG trap or PROMPT_COMMAND
#     to use preexec and precmd instead. Preexisting usages will be
#     preserved, but doing so manually may be less surprising.
#
#  Note: This module requires two Bash features which you must not otherwise be
#  using: the "DEBUG" trap, and the "PROMPT_COMMAND" variable. If you override
#  either of these after bash-preexec has been installed it will most likely break.

# Tell shellcheck what kind of file this is.
# shellcheck shell=bash

# Make sure this is bash that's running and return otherwise.
# Use POSIX syntax for this line:
if [ -z "${BASH_VERSION-}" ]; then
    return 1
fi

# We only support Bash 3.1+.
# Note: BASH_VERSINFO is first available in Bash-2.0.
if [[ -z "${BASH_VERSINFO-}" ]] || (( BASH_VERSINFO[0] < 3 || (BASH_VERSINFO[0] == 3 && BASH_VERSINFO[1] < 1) )); then
    return 1
fi

# Avoid duplicate inclusion
if [[ -n "${bash_preexec_imported:-}" || -n "${__bp_imported:-}" ]]; then
    return 0
fi
bash_preexec_imported="defined"

# WARNING: This variable is no longer used and should not be relied upon.
# Use ${bash_preexec_imported} instead.
# shellcheck disable=SC2034
__bp_imported="${bash_preexec_imported}"

# Should be available to each precmd and preexec
# functions, should they want it. $? and $_ are available as $? and $_, but
# $PIPESTATUS is available only in a copy, $BP_PIPESTATUS.
# TODO: Figure out how to restore PIPESTATUS before each precmd or preexec
# function.
__bp_last_ret_value="$?"
BP_PIPESTATUS=("${PIPESTATUS[@]}")
__bp_last_argument_prev_command="$_"

__bp_inside_precmd=0
__bp_inside_preexec=0

# Initial PROMPT_COMMAND string that is removed from PROMPT_COMMAND post __bp_install
# shellcheck disable=SC2016
__bp_install_string='__bp_install "$_"'

# Fails if any of the given variables are readonly
# Reference https://stackoverflow.com/a/4441178
__bp_require_not_readonly() {
    local var
    for var; do
        if ! ( unset "$var" 2> /dev/null ); then
            echo "bash-preexec requires write access to ${var}" >&2
            return 1
        fi
    done
}

# Remove ignorespace and or replace ignoreboth from HISTCONTROL
# so we can accurately invoke preexec with a command from our
# history even if it starts with a space.
__bp_adjust_histcontrol() {
    local histcontrol
    histcontrol="${HISTCONTROL:-}"
    histcontrol="${histcontrol//ignorespace}"
    # Replace ignoreboth with ignoredups
    if [[ "$histcontrol" == *"ignoreboth"* ]]; then
        histcontrol="ignoredups:${histcontrol//ignoreboth}"
    fi
    export HISTCONTROL="$histcontrol"
}

# This variable describes whether we are currently in "interactive mode";
# i.e. whether this shell has just executed a prompt and is waiting for user
# input.  It documents whether the current command invoked by the trace hook is
# run interactively by the user; it's set immediately after the prompt hook,
# and unset as soon as the trace hook is run.
__bp_preexec_interactive_mode=""

# These global arrays are used to add functions to be run before, or after,
# prompts.  Note that Bash < 4.2 does not have the "-g" option of the "declare"
# builtin.  We actually do not need to explicitly initialize these arrays.
#declare -ga precmd_functions
#declare -ga preexec_functions

# Trims leading and trailing whitespace from $2 and writes it to the variable
# name passed as $1
__bp_trim_whitespace() {
    local var=${1:?} text=${2:-}
    text="${text#"${text%%[![:space:]]*}"}"   # remove leading whitespace characters
    text="${text%"${text##*[![:space:]]}"}"   # remove trailing whitespace characters
    printf -v "$var" '%s' "$text"
}


# Trims whitespace and removes any leading or trailing semicolons from $2 and
# writes the resulting string to the variable name passed as $1. This also
# removes the no-op colons, which are converted from the hooks to remove. Used
# for manipulating substrings in PROMPT_COMMAND
__bp_sanitize_string() {
    local var=${1:?} sanitized=${2:-}

    local unset_extglob=
    if ! shopt -q extglob; then
        unset_extglob=yes
        shopt -s extglob
    fi

    # We specify newline character through the variable `nl' because $'\n'
    # inside "${var//...}" is treated literally as "\$'\\n'" when `extquote' is
    # unset (shopt -u extquote). (Note: Bash 5.2's extquote seems to be buggy.)
    local tmp nl=$'\n'
    while
        # Note: Quoting parameter expansions $nl in PAT of ${var//PAT/REP} is
        # required by shellcheck.  On the other hand, we should not quote the
        # parameter expansions $nl in REP because the quotes will remain in the
        # replaced result with `shopt -s compat42'.
        # Note: We use ?(+([[:blank:]])) instead of *([[:blank:]]) to work
        # around a bug of Bash 3.2 that *(...) is not properly processed as
        # extglob at the beginning of the pattern in ${var//pat/rep}.
        tmp="${sanitized//?(+([[:blank:]]))[";$nl"]*([[:blank:]]):*([[:blank:]])[";$nl"]*([[:blank:]])/$nl}"
        [[ "$tmp" != "$sanitized" ]]
    do
        sanitized="$tmp"
    done
    sanitized="${sanitized#:*([[:blank:]])[";$nl"]}"
    sanitized="${sanitized%[";$nl"]*([[:blank:]]):}"
    __bp_trim_whitespace sanitized "$sanitized"
    sanitized=${sanitized%;}
    sanitized=${sanitized#;}
    __bp_trim_whitespace sanitized "$sanitized"
    if [[ "$sanitized" == ":" ]]; then
        sanitized=
    fi
    printf -v "$var" '%s' "$sanitized"

    if [[ -n "$unset_extglob" ]]; then
        shopt -u extglob
    fi
}


# Bash >= 5.1 supports the array version of PROMPT_COMMAND.
__bp_use_array_prompt_command() {
    (( BASH_VERSINFO[0] > 5 || (BASH_VERSINFO[0] == 5 && BASH_VERSINFO[1] >= 1) ))
}


# Remove $1 and sanitize each elements of PROMPT_COMMAND. We want to keep
# PROMPT_COMMAND scalar in bash < 5.1 because some configuration tests the
# support for the array PROMPT_COMMAND by checking the array attribute of
# PROMPT_COMMAND.
__bp_remove_command_from_prompt_command() {
    local removed_command="${1-}"
    if __bp_use_array_prompt_command; then
        local i sanitized_prompt_command
        for i in "${!PROMPT_COMMAND[@]}"; do
            sanitized_prompt_command="${PROMPT_COMMAND[i]:-}"
            sanitized_prompt_command="${sanitized_prompt_command//"$removed_command"/:}"
            __bp_sanitize_string sanitized_prompt_command "$sanitized_prompt_command"
            if [[ -n "$sanitized_prompt_command" ]]; then
                PROMPT_COMMAND[i]="$sanitized_prompt_command"
            else
                unset -v 'PROMPT_COMMAND[i]'
            fi
        done
    else
        local sanitized_prompt_command="${PROMPT_COMMAND:-}"
        sanitized_prompt_command="${sanitized_prompt_command//"$removed_command"/:}" # no-op
        __bp_sanitize_string PROMPT_COMMAND "$sanitized_prompt_command"
    fi
}


# This function is installed as part of the PROMPT_COMMAND;
# It sets a variable to indicate that the prompt was just displayed,
# to allow the DEBUG trap to know that the next command is likely interactive.
__bp_interactive_mode() {
    if [[ "${1-}" != "force" && ! "${BATS_VERSION-}" ]] && (( ${#FUNCNAME[*]} > 1 )); then
        # When this function is not called from the top level, the current
        # function call is probably performed via PROMPT_COMMAND saved by
        # another framework (e.g., starship). In this case, we do not want to
        # turn on the "interactive mode" here.
        return 0
    fi

    __bp_preexec_interactive_mode="on"
}


# This function is installed as part of the PROMPT_COMMAND.
# It will invoke any functions defined in the precmd_functions array.
__bp_precmd_invoke_cmd() {
    # Save the returned value and the last argument from our last command, and
    # the returned value from each process in its pipeline. Note: this MUST be
    # the first thing done in this function.
    # BP_PIPESTATUS may be unused, ignore
    # shellcheck disable=SC2034
    __bp_last_ret_value="$?" __bp_last_argument_prev_command="$_" \
        BP_PIPESTATUS=("${PIPESTATUS[@]}")


    # Don't invoke precmds if we are inside an execution of an "original
    # prompt command" by another precmd execution loop. This avoids infinite
    # recursion.
    if (( __bp_inside_precmd > 0 )); then
        return "$__bp_last_ret_value"
    fi

    # Check and adjust PROMPT_COMMAND to make sure that PROMPT_COMMAND has the
    # form "__bp_precmd_invoke_cmd; ...; __bp_interactive_mode"
    if ! __bp_install_prompt_command; then
        if [[ "${1-}" != "force" && ! "${BATS_VERSION-}" ]] && (( ${#FUNCNAME[*]} > 1 )); then
            # When PROMPT_COMMAND is already properly set up but this function
            # is not called from the top level, the current function call is
            # probably performed via PROMPT_COMMAND saved by another framework
            # (e.g., starship). In this case, we do not need to invoke precmd
            # because it is supposed to be already processed by the top-level
            # __bp_precmd_invoke_cmd.
            return "$__bp_last_ret_value"
        fi
    fi

    local __bp_inside_precmd=1
    __bp_invoke_precmd_functions "$__bp_last_ret_value" "$__bp_last_argument_prev_command"

    __bp_set_ret_value "$__bp_last_ret_value" "$__bp_last_argument_prev_command"
}

# This function invokes every function defined in the "precmd_functions" array.
# This function receives the arguments $1 and $2 for $?  and $_, respectively,
# which will be set for each precmd function. This function returns the last
# non-zero exit status of the hook functions. If there is no error, this
# function returns 0.
__bp_invoke_precmd_functions() {
    local lastexit=$1 lastarg=$2
    # Invoke every function defined in our function array.
    local precmd_function
    local precmd_function_ret_value
    local precmd_ret_value=0
    for precmd_function in "${precmd_functions[@]}"; do

        # Only execute this function if it actually exists.
        # Test existence of functions with: declare -[Ff]
        if type -t "$precmd_function" 1>/dev/null; then
            __bp_set_ret_value "$lastexit" "$lastarg"
            # Quote our function invocation to prevent issues with IFS
            "$precmd_function"
            precmd_function_ret_value=$?
            if [[ "$precmd_function_ret_value" != 0 ]]; then
                precmd_ret_value="$precmd_function_ret_value"
            fi
        fi
    done

    __bp_set_ret_value "$precmd_ret_value"
}

# Sets a return value in $?. We may want to get access to the $? variable in our
# precmd functions. This is available for instance in zsh. We can simulate it in bash
# by setting the value here.
__bp_set_ret_value() {
    return ${1:+"$1"}
}

__bp_in_prompt_command() {

    local prompt_command_array IFS=$'\n;'
    read -rd '' -a prompt_command_array <<< "${PROMPT_COMMAND[*]:-}"

    local trimmed_arg
    __bp_trim_whitespace trimmed_arg "${1:-}"

    local command trimmed_command
    for command in "${prompt_command_array[@]:-}"; do
        __bp_trim_whitespace trimmed_command "$command"
        if [[ "$trimmed_command" == "$trimmed_arg" ]]; then
            return 0
        fi
    done

    return 1
}

__bp_load_this_command_from_history() {
    this_command=$(LC_ALL=C HISTTIMEFORMAT='' builtin history 1)
    this_command="${this_command#*[[:digit:]][* ] }"

    # Sanity check to make sure we have something to invoke our function with.
    [[ -n "$this_command" ]]
}

# This function is installed as the DEBUG trap.  It is invoked before each
# interactive prompt display.  Its purpose is to inspect the current
# environment to attempt to detect if the current command is being invoked
# interactively, and invoke 'preexec' if so.
__bp_preexec_invoke_exec() {
    local lastarg=$_

    # Don't invoke preexecs if we are inside of another preexec.
    if (( __bp_inside_preexec > 0 )); then
        return
    fi
    local __bp_inside_preexec=1

    # Checks if the file descriptor is not standard out (i.e. '1')
    # __bp_delay_install checks if we're in test. Needed for bats to run.
    # Prevents preexec from being invoked for functions in PS1
    if [[ ! -t 1 && -z "${__bp_delay_install:-}" ]]; then
        return
    fi

    if [[ -n "${COMP_POINT:-}" || -n "${READLINE_POINT:-}" ]]; then
        # We're in the middle of a completer or a keybinding set up by "bind
        # -x".  This obviously can't be an interactively issued command.
        return
    fi
    if [[ -z "${__bp_preexec_interactive_mode:-}" ]]; then
        # We're doing something related to displaying the prompt.  Let the
        # prompt set the title instead of me.
        return
    else
        # If we're in a subshell, then the prompt won't be re-displayed to put
        # us back into interactive mode, so let's not set the variable back.
        # In other words, if you have a subshell like
        #   (sleep 1; sleep 2)
        # You want to see the 'sleep 2' as a set_command_title as well.
        if [[ 0 -eq "${BASH_SUBSHELL:-}" ]]; then
            __bp_preexec_interactive_mode=""
        fi
    fi

    if  __bp_in_prompt_command "${BASH_COMMAND:-}"; then
        # If we're executing something inside our prompt_command then we don't
        # want to call preexec. Bash prior to 3.1 can't detect this at all :/
        __bp_preexec_interactive_mode=""
        return
    fi

    # Save the contents of $_ so that it can be restored later on.
    # https://stackoverflow.com/questions/40944532/bash-preserve-in-a-debug-trap#40944702
    __bp_last_argument_prev_command=$lastarg

    local this_command
    __bp_load_this_command_from_history || return

    __bp_invoke_preexec_functions "${__bp_last_ret_value:-}" "$__bp_last_argument_prev_command" "$this_command"
    local preexec_ret_value=$?

    # Restore the last argument of the last executed command, and set the return
    # value of the DEBUG trap to be the return code of the last preexec function
    # to return an error.
    # If `extdebug` is enabled a non-zero return value from any preexec function
    # will cause the user's command not to execute.
    # Run `shopt -s extdebug` to enable
    __bp_set_ret_value "$preexec_ret_value" "$__bp_last_argument_prev_command"
}

__bp_invoke_preexec_from_ps0() {
    __bp_last_argument_prev_command="${1:-}"

    local this_command
    __bp_load_this_command_from_history || return

    __bp_invoke_preexec_functions "${__bp_last_ret_value:-}" "$__bp_last_argument_prev_command" "$this_command"
}

# This function invokes every function defined in the "preexec_functions"
# array.  This function receives the arguments $1 and $2 for $?  and $_,
# respectively, which will be set for each preexec function.  The third
# argument $3 specifies the user command that is going to be executed
# (corresponding to BASH_COMMAND in the DEBUG trap).  This function returns the
# last non-zero exit status from the preexec functions.  If there is no error,
# this function returns `0`.
__bp_invoke_preexec_functions() {
    local lastexit=$1 lastarg=$2 this_command=$3
    local preexec_function
    local preexec_function_ret_value
    local preexec_ret_value=0
    for preexec_function in "${preexec_functions[@]:-}"; do

        # Only execute each function if it actually exists.
        # Test existence of function with: declare -[fF]
        if type -t "$preexec_function" 1>/dev/null; then
            __bp_set_ret_value "$lastexit" "$lastarg"
            # Quote our function invocation to prevent issues with IFS
            "$preexec_function" "$this_command"
            preexec_function_ret_value="$?"
            if [[ "$preexec_function_ret_value" != 0 ]]; then
                preexec_ret_value="$preexec_function_ret_value"
            fi
        fi
    done
    __bp_set_ret_value "$preexec_ret_value"
}

__bp_hook_preexec_into_debug() {
    local trap_string
    trap_string=$(trap -p DEBUG)
    trap '__bp_preexec_invoke_exec "$_"' DEBUG

    # Preserve any prior DEBUG trap as a preexec function
    eval "local trap_argv=(${trap_string:-})"
    local prior_trap=${trap_argv[2]:-}
    if [[ -n "$prior_trap" ]]; then
        eval '__bp_original_debug_trap() {
            '"$prior_trap"'
        }'
        preexec_functions+=(__bp_original_debug_trap)
    fi

    # Adjust our HISTCONTROL Variable if needed.
    __bp_adjust_histcontrol

    # Issue #25. Setting debug trap for subshells causes sessions to exit for
    # backgrounded subshell commands (e.g. (pwd)& ). Believe this is a bug in Bash.
    #
    # Disabling this by default. It can be enabled by setting this variable.
    if [[ -n "${__bp_enable_subshells:-}" ]]; then

        # Set so debug trap will work be invoked in subshells.
        set -o functrace > /dev/null 2>&1
        shopt -s extdebug > /dev/null 2>&1
    fi
}

__bp_hook_preexec_into_ps0() {
    # shellcheck disable=SC2016
    PS0=${PS0-}'${ __bp_invoke_preexec_from_ps0 "$_" >&2; }'

    # Adjust our HISTCONTROL Variable if needed.
    __bp_adjust_histcontrol
}

if (( BASH_VERSINFO[0] > 5 || (BASH_VERSINFO[0] == 5 && BASH_VERSINFO[1] >= 3) )); then
    __bp_hook_preexec_proc=__bp_hook_preexec_into_ps0
else
    __bp_hook_preexec_proc=__bp_hook_preexec_into_debug
fi

__bp_install() {
    local lastexit=$? lastarg=$_
    # Exit if we already have this installed.
    # shellcheck disable=SC2016
    if [[ "${PROMPT_COMMAND[*]:-}" == *'__bp_precmd_invoke_cmd "$_"'* ]]; then
        return 1
    fi

    "$__bp_hook_preexec_proc"

    # Remove setting our trap install string and sanitize the existing prompt command string
    __bp_remove_command_from_prompt_command "$__bp_install_string"

    __bp_install_prompt_command || true

    # Add two functions to our arrays for convenience
    # of definition.
    precmd_functions+=(precmd)
    preexec_functions+=(preexec)

    # Invoke our two functions manually that were added to $PROMPT_COMMAND
    __bp_set_ret_value "$lastexit" "$lastarg"
    __bp_precmd_invoke_cmd force
    __bp_interactive_mode force
}

# Note: We need to add the "trace" attribute to these functions so that "trap
# ... DEBUG" inside "__bp_install" and "__bp_hook_preexec_into_debug" takes
# effect even when there is an existing DEBUG trap.
declare -ft __bp_install __bp_hook_preexec_into_debug

# Encloses PROMPT_COMMAND hooks within __bp_precmd_invoke_cmd and
# __bp_interactive_mode. If all the PROMPT_COMMAND hooks are already surrounded
# by __bp_precmd_invoke_cmd and __bp_interactive_mode, the function exits with
# status 1.
__bp_install_prompt_command() {
    local prompt_command="${PROMPT_COMMAND:-}"
    if __bp_use_array_prompt_command; then
        local IFS=$'\n'
        prompt_command="${PROMPT_COMMAND[*]:-}"
        IFS=$' \t\n'
    fi

    # Exit if we already have a properly set-up hooks in PROMPT_COMMAND
    # shellcheck disable=SC2016
    local prologue='__bp_precmd_invoke_cmd "$_"'
    local epilogue='__bp_interactive_mode'
    if [[ "$prompt_command" == "$prologue"$'\n'* && "$prompt_command" == *$'\n'"$epilogue" ]]; then
        return 1
    fi

    __bp_remove_command_from_prompt_command "$prologue"
    __bp_remove_command_from_prompt_command "$epilogue"

    # Install our hooks in PROMPT_COMMAND to allow our trap to know when we've
    # actually entered something.
    # shellcheck disable=SC2128,SC2178 # PROMPT_COMMAND is not an array in bash <= 5.0
    PROMPT_COMMAND=$prologue${PROMPT_COMMAND:+$'\n'$PROMPT_COMMAND}
    if __bp_use_array_prompt_command; then
        PROMPT_COMMAND+=("$epilogue")
    else
        # shellcheck disable=SC2179 # PROMPT_COMMAND is not an array in bash <= 5.0
        PROMPT_COMMAND+=$'\n'$epilogue
    fi
    return 0
}

# Sets an installation string as part of our PROMPT_COMMAND to install
# after our session has started. This allows bash-preexec to be included
# at any point in our bash profile.
__bp_install_after_session_init() {
    # bash-preexec needs to modify these variables in order to work correctly
    # if it can't, just stop the installation
    __bp_require_not_readonly PROMPT_COMMAND HISTCONTROL HISTTIMEFORMAT || return
    if [[ $__bp_hook_preexec_proc == '__bp_hook_preexec_into_ps0' ]]; then
        __bp_require_not_readonly PS0 || return
    fi

    if __bp_use_array_prompt_command; then
        PROMPT_COMMAND+=("${__bp_install_string}")
    else
        local sanitized_prompt_command
        __bp_sanitize_string sanitized_prompt_command "${PROMPT_COMMAND:-}"
        if [[ -n "$sanitized_prompt_command" ]]; then
            # shellcheck disable=SC2178 # PROMPT_COMMAND is not an array in bash <= 5.0
            PROMPT_COMMAND=${sanitized_prompt_command}$'\n'
        fi
        # shellcheck disable=SC2179 # PROMPT_COMMAND is not an array in bash <= 5.0
        PROMPT_COMMAND+=${__bp_install_string}
    fi
}

# Run our install so long as we're not delaying it.
if [[ -z "${__bp_delay_install:-}" ]]; then
    __bp_install_after_session_init
fi
# -- END BASH-PREEXEC.SH --

}
_install_bash_preexec
unset -f _install_bash_preexec

# -- BEGIN ITERM2 CUSTOMIZATIONS --

# We don't care about whitespace, but users care about not changing their histcontrol variables.
# We overwrite the upstream __bp_adjust_histcontrol function whcih gets called from the next
# PROMPT_COMMAND invocation.
function __bp_adjust_histcontrol() {
  true
}

function iterm2_begin_osc {
  printf "\033]"
}

function iterm2_end_osc {
  printf "\007"
}

# Percent-encode $1 per RFC 3986, preserving unreserved characters and the path
# separator. LC_CTYPE=C/LC_COLLATE=C force byte-wise iteration so each UTF-8 byte is
# encoded individually (matching how the receiver decodes the URL). Stores the
# result in the global _iterm2_encoded_path rather than printing it, so the caller
# reads a variable instead of forking a command substitution on every prompt.
function iterm2_encode_path() {
  local _iterm2_path="$1"
  local _iterm2_i _iterm2_ch _iterm2_hexch _iterm2_out=""
  local LC_CTYPE=C LC_COLLATE=C LC_ALL=
  for ((_iterm2_i = 0; _iterm2_i < ${#_iterm2_path}; ++_iterm2_i)); do
    _iterm2_ch="${_iterm2_path:_iterm2_i:1}"
    if [[ "$_iterm2_ch" =~ [/._~A-Za-z0-9-] ]]; then
      _iterm2_out+="$_iterm2_ch"
    else
      # printf treats byte values > 127 as negative and left-pads with FF, so
      # keep only the low two hex digits.
      printf -v _iterm2_hexch "%02X" "'$_iterm2_ch"
      _iterm2_out+="%${_iterm2_hexch: -2:2}"
    fi
  done
  _iterm2_encoded_path="$_iterm2_out"
}

function iterm2_print_state_data() {
  local _iterm2_hostname="${iterm2_hostname-}"
  if [ -z "${iterm2_hostname:-}" ]; then
    _iterm2_hostname=$(hostname -f 2>/dev/null)
  fi
  # Sanitize the authority: a username or hostname with a URL-structural character
  # (/, ?, #, or whitespace) would silently restructure the URL - recording the
  # wrong directory, or (since the machineID query still parses) poisoning localhost
  # detection with a truncated host. Keep only a safe set so a malformed label
  # degrades to a clean name. The username keeps @ (an AD login like alice@corp.com
  # survives, since URL parsers split on the LAST @).
  local _iterm2_user="${USER//[^A-Za-z0-9._@-]/}"
  _iterm2_hostname="${_iterm2_hostname//[^A-Za-z0-9._-]/}"
  # OSC 7: report username, hostname, and working directory as a single file URL.
  # This supersedes the older 1337;RemoteHost and 1337;CurrentDir codes.
  local _iterm2_encoded_path=""
  iterm2_encode_path "$PWD"
  # Append the machine identity (computed once at source time, see below).
  local _iterm2_url="file://${_iterm2_user}@${_iterm2_hostname}${_iterm2_encoded_path}?machineID=${_iterm2_machine_id}"
  iterm2_begin_osc
  printf "7;%s" "$_iterm2_url"
  iterm2_end_osc

  iterm2_print_user_vars
}

# Usage: iterm2_set_user_var key value
function iterm2_set_user_var() {
  # Encoded before the sequence starts and written whole: tmux 2.6 to 3.0a give up on a sequence
  # that pauses for 100 ms partway and show the rest as text.
  local _iterm2_value
  _iterm2_value=$(printf "%s" "$2" | base64 | tr -d '\n')
  printf "\033]1337;SetUserVar=%s=%s\007" "$1" "$_iterm2_value"
}

if [ -z "$(type -t iterm2_print_user_vars)" ] || [ "$(type -t iterm2_print_user_vars)" != function ]; then
  # iterm2_print_user_vars is not already defined. Provide a no-op default version.
  #
  # Users can write their own version of this function. It should call
  # iterm2_set_user_var but not produce any other output.
  function iterm2_print_user_vars() {
    true
  }
fi

# OSC 133 aid: per-command identifier the receiver uses to target a
# specific mark for D-by-aid (and cascade-close when an outer command
# like ssh dies before its inner remote shell's D arrives). The salt is
# rolled once at shell-source time; the counter increments per prompt
# cycle in __iterm2_prompt_command.
export ITERM2_AID_SALT="${RANDOM}${RANDOM}"
export ITERM2_AID_COUNTER=0
# Pre-seeded so emissions before the first __iterm2_prompt_command have a
# defined aid value rather than the empty string.
export ITERM2_CURRENT_AID="${ITERM2_AID_SALT}-0"

function iterm2_prompt_prefix() {
  iterm2_begin_osc
  printf "133;D;\$?;aid=%s" "$ITERM2_CURRENT_AID"
  iterm2_end_osc
}

function iterm2_prompt_mark() {
  iterm2_begin_osc
  printf "133;A;aid=%s" "$ITERM2_CURRENT_AID"
  iterm2_end_osc
}

# Semantic Prompt k=s — non-editable secondary (PS2). Used to wrap PS2 so the
# receiver can subtract the PS2 prefix cells from the typed-command region and
# so paste-helpers can advance past PS2 lines (issue 5749).
function iterm2_ps2_mark() {
  iterm2_begin_osc
  printf "133;A;k=s;aid=%s" "$ITERM2_CURRENT_AID"
  iterm2_end_osc
}

function iterm2_prompt_suffix() {
  iterm2_begin_osc
  printf "133;B;aid=%s" "$ITERM2_CURRENT_AID"
  iterm2_end_osc
}

function iterm2_print_version_number() {
  iterm2_begin_osc
  printf "1337;ShellIntegrationVersion=23;shell=bash"
  iterm2_end_osc
}


# If hostname -f is slow on your system, set iterm2_hostname before sourcing this script.
# On macOS we run `hostname -f` every time because it is fast.
if [ -z "${iterm2_hostname:-}" ]; then
  if [ "$(uname)" != "Darwin" ]; then
    iterm2_hostname=$(hostname -f 2>/dev/null)
    # some flavors of BSD (i.e. NetBSD and OpenBSD) don't have the -f option
    if [ $? -ne 0 ]; then
      iterm2_hostname=$(hostname)
    fi
  fi
fi

# Machine identity for OSC 7 localhost detection, computed ONCE and cached in a
# NON-EXPORTED shell variable (a plain assignment, never `export`, so it cannot
# cross ssh) as "1:<hmac>". We HMAC kern.bootsessionuuid with a fixed protocol key
# rather than sending the raw per-boot UUID on the wire; iTerm2 HMACs its own the
# same way and compares. $OSTYPE is a bash builtin (no fork); the sysctl and
# openssl run once here, not per prompt. A known non-Darwin host can't be this Mac,
# so it sends the empty value ("1:"); a Darwin failure, or an OS we cannot determine
# at all (empty $OSTYPE), sends "0:" (identity unavailable, so the receiver falls
# back to hostname matching).
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

iterm2_maybe_print_cr() {
  if [ "$TERM_PROGRAM" = "iTerm.app" ]; then
    printf "\r"
  fi
}

# Runs after interactively edited command but before execution
__iterm2_preexec() {
    # Save the returned value from our last command
    __iterm2_last_ret_value="$?"

    iterm2_begin_osc
    printf "133;C;aid=%s" "$ITERM2_CURRENT_AID"
    iterm2_maybe_print_cr
    iterm2_end_osc
    # If PS1 still has the value we set it to in iterm2_preexec_invoke_cmd then
    # restore it to its original value. It might have changed if you have
    # another PROMPT_COMMAND (like liquidprompt) that modifies PS1.
    if [ -n "${ITERM_ORIG_PS1+xxx}" -a "$PS1" = "$ITERM_PREV_PS1" ]
    then
      export PS1="$ITERM_ORIG_PS1"
    fi
    # Same dance for PS2: restore the un-decorated value so the user's command
    # doesn't see our escape sequences (and so the next prompt cycle re-wraps a
    # clean PS2). Bail if the user changed PS2 mid-command.
    if [ -n "${ITERM_ORIG_PS2+1}" -a "$PS2" = "$ITERM_PREV_PS2" ]
    then
      export PS2="$ITERM_ORIG_PS2"
    fi
    iterm2_ran_preexec="yes"
    # preexec functions can return nonzero to prevent user's command from running.
    return 0
}

# Prints the current directory and hostname control sequences. Modifies PS1 to
# add the FinalTerm A and B codes to locate the prompt.
function __iterm2_prompt_command () {
    __iterm2_last_ret_value="$?"

    if [[ -z "${iterm2_ran_preexec:-}" ]]
    then
        # This code path is taken when you press ^C while entering a command.
        # I observed this behavior in CentOS 7.2 and macOS "GNU bash, version 5.0.18(1)-release".
        ( exit $__iterm2_last_ret_value )
        __iterm2_preexec ""
        __bp_set_ret_value "$__iterm2_last_ret_value" "$__bp_last_argument_prev_command"
    fi
    iterm2_ran_preexec=""

    # This is an iTerm2 addition to try to work around a problem in the
    # original preexec.bash.
    # When the PS1 has command substitutions, this gets invoked for each
    # substitution and each command that's run within the substitution, which
    # really adds up. It would be great if we could do something like this at
    # the end of this script:
    #   PS1="$(iterm2_prompt_prefix)$PS1($iterm2_prompt_suffix)"
    # and have iterm2_prompt_prefix set a global variable that tells precmd not to
    # output anything and have iterm2_prompt_suffix reset that variable.
    # Unfortunately, command substitutions run in subshells and can't
    # communicate to the outside world.
    # Instead, we have this workaround. We save the original value of PS1 in
    # $ITERM_ORIG_PS1. Then each time this function is run (it's called from
    # PROMPT_COMMAND just before the prompt is shown) it will change PS1 to a
    # string without any command substitutions by doing eval on ITERM_ORIG_PS1. At
    # this point ITERM_PREEXEC_INTERACTIVE_MODE is still the empty string, so preexec
    # won't produce output for command substitutions.

    # The first time this is called ITERM_ORIG_PS1 is unset. This tests if the variable
    # is undefined (not just empty) and initializes it. We can't initialize this at the
    # top of the script because it breaks with liquidprompt. liquidprompt wants to
    # set PS1 from a PROMPT_COMMAND that runs just before us. Setting ITERM_ORIG_PS1
    # at the top of the script will overwrite liquidprompt's PS1, whose value would
    # never make it into ITERM_ORIG_PS1. Issue 4532. It's important to check
    # if it's undefined before checking if it's empty because some users have
    # bash set to error out on referencing an undefined variable.
    if [ -z "${ITERM_ORIG_PS1+xxx}" ]
    then
      # ITERM_ORIG_PS1 always holds the last user-set value of PS1.
      # You only get here on the first time iterm2_preexec_invoke_cmd is called.
      export ITERM_ORIG_PS1="$PS1"
    fi

    # If you want to generate PS1 dynamically from PROMPT_COMMAND, the best way
    # to do it is to define a function named iterm2_generate_ps1 that sets PS1.
    # Issue 5964. Other shells don't have this issue because they don't need
    # such extremes to get precmd and preexec.
    if [ -n "$(type -t iterm2_generate_ps1)" ] && [ "$(type -t iterm2_generate_ps1)" = function ]; then
      iterm2_generate_ps1
    fi


    if [[ "$PS1" != "$ITERM_PREV_PS1" ]]
    then
      export ITERM_ORIG_PS1="$PS1"
    fi

    # PS2 parallel of the PS1 dance above. First time through ITERM_ORIG_PS2 is
    # unset, so capture the user's PS2 (which may be the shell default "> ").
    # On subsequent cycles, if PS2 differs from what we last wrote, the user
    # (or another precmd) changed it and we re-capture.
    if [ -z "${ITERM_ORIG_PS2+1}" ]
    then
      export ITERM_ORIG_PS2="$PS2"
    fi
    if [[ "$PS2" != "${ITERM_PREV_PS2-}" ]]
    then
      export ITERM_ORIG_PS2="$PS2"
    fi

    # Get the value of the prompt prefix, which will change $?
    \local iterm2_prompt_prefix_value="$(iterm2_prompt_prefix)"

    # Roll the per-command aid AFTER D for the previous command has been
    # captured (above) and BEFORE A/B for the new command get captured
    # below. The just-finished command's A/B/C/D all share the OLD aid;
    # the upcoming command's A/B/C/D all share the NEW one.
    ITERM2_AID_COUNTER=$((ITERM2_AID_COUNTER + 1))
    ITERM2_CURRENT_AID="${ITERM2_AID_SALT}-${ITERM2_AID_COUNTER}"

    # Add the mark unless the prompt includes '$(iterm2_prompt_mark)' as a substring.
    if [[ $ITERM_ORIG_PS1 != *'$(iterm2_prompt_mark)'* && x${ITERM2_SQUELCH_MARK-} = x ]]
    then
      iterm2_prompt_prefix_value="$iterm2_prompt_prefix_value$(iterm2_prompt_mark)"
    fi

    # Send escape sequences with current directory and hostname.
    iterm2_print_state_data

    # Reset $? to its saved value, which might be used in $ITERM_ORIG_PS1.
    __bp_set_ret_value "$__iterm2_last_ret_value" "$__bp_last_argument_prev_command"

    # Set PS1 to various escape sequences, the user's preferred prompt, and more escape sequences.
    export PS1="\[$iterm2_prompt_prefix_value\]$ITERM_ORIG_PS1\[$(iterm2_prompt_suffix)\]"

    # Wrap PS2 with k=s (Semantic Prompt secondary). Receiver records the PS2
    # prefix cells as an excluded subrange on the active primary mark and uses
    # the marker to unblock Advanced Paste's "Wait for shell prompt" between
    # continuation lines (issue 5749). Opt out with ITERM2_SQUELCH_PS2_MARK.
    if [[ x${ITERM2_SQUELCH_PS2_MARK-} = x ]]
    then
      export PS2="\[$(iterm2_ps2_mark)\]$ITERM_ORIG_PS2\[$(iterm2_prompt_suffix)\]"
    fi

    # Save the value we just set PS1/PS2 to so if the user changes them later
    # we'll detect it and refresh ITERM_ORIG_*.
    export ITERM_PREV_PS1="$PS1"
    export ITERM_PREV_PS2="$PS2"
    __bp_set_ret_value "$__iterm2_last_ret_value" "$__bp_last_argument_prev_command"
}

# Install my function
preexec_functions+=(__iterm2_preexec)

iterm2_print_state_data
iterm2_print_version_number
fi

# -- END ITERM2 CUSTOMIZATIONS --



# Put iTerm2's uploaded it2 on PATH, ahead of the shell function below. Exported, so a program
# started from this shell passes it on: a Claude Code hook runs through `sh -c` and an agent's
# Bash tool does too, and neither sees a shell function. Done here rather than from the app
# because the real PATH is only known in the login shell; the conductor cannot express a prepend
# (its setenv does no re-expansion) and an absolute value there would break conductor.sh itself.
# Guarded on the directory existing, so a host iTerm2 never uploaded to keeps a clean PATH. Moved
# to the front if it is already on PATH, so iTerm2's it2 wins over any other (a login profile's
# path_helper or a `brew shellenv` may have put other directories ahead of it), and never
# duplicated, so re-sourcing does not stack copies.
# Split with read rather than a pattern substitution, which macOS's bash 3.2 quotes differently.
if [ -d "${HOME}/.iterm2/bin" ]; then
  IFS=: read -r -a _iterm2_dirs <<< "$PATH"
  _iterm2_path="${HOME}/.iterm2/bin"
  for _iterm2_dir in ${_iterm2_dirs[@]+"${_iterm2_dirs[@]}"}; do
    [ "$_iterm2_dir" = "${HOME}/.iterm2/bin" ] || _iterm2_path="${_iterm2_path}:${_iterm2_dir}"
  done
  PATH="$_iterm2_path"
  export PATH
  unset _iterm2_dirs _iterm2_dir _iterm2_path
fi

# it2 CLI over iTerm2 SSH integration: unless it2 already exists, define it as a
# function that materializes the embedded copy on first use (named by content hash,
# so a shipped update replaces a stale one). Needs python3; it2.py reads
# IT2_SOCK/IT2_NONCE from the environment set by SSH integration.
if ! command -v it2 > /dev/null 2>&1; then
  it2() {
    command -v python3 > /dev/null 2>&1 || { printf 'it2: python3 is required\n' >&2; return 1; }
    if [ ! -f "${HOME}/.iterm2/it2.f1f13ef87d320f31.py" ]; then
      python3 -c 'import base64,gzip,os,sys,tempfile; d=os.path.expanduser("~/.iterm2"); os.makedirs(d,exist_ok=True); data=gzip.decompress(base64.b64decode(sys.argv[1])); fd,tmp=tempfile.mkstemp(dir=d); os.write(fd,data); os.close(fd); os.replace(tmp,sys.argv[2])' "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" "${HOME}/.iterm2/it2.f1f13ef87d320f31.py" || return 1
    fi
    command python3 "${HOME}/.iterm2/it2.f1f13ef87d320f31.py" "$@"
  }
  export -f it2 2> /dev/null
fi
