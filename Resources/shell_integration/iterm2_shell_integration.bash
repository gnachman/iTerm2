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
  printf "1337;ShellIntegrationVersion=25;shell=bash"
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

# Install Shell Integration & Utilities used to alias it2ssh to a copy in .iterm2, which hides
# the newer it2ssh iTerm2 puts on PATH. Remove that alias, and only that alias, when the it2ssh
# PATH finds first is the one inside iTerm2's app bundle. Done at the first prompt because the
# installer appended the alias after this script. Reads `alias` rather than BASH_ALIASES, which
# bash 3.2 lacks.
function __iterm2_drop_stale_it2ssh_alias () {
    local definition found
    definition="$(alias it2ssh 2>/dev/null)" || return 0
    [[ "$definition" == "alias it2ssh='"*"/.iterm2/it2ssh'" ]] || return 0
    found="$(type -P it2ssh)" || return 0
    [[ "$found" == */Contents/Resources/utilities/it2ssh ]] && unalias it2ssh
    return 0
}

# Prints the current directory and hostname control sequences. Modifies PS1 to
# add the FinalTerm A and B codes to locate the prompt.
function __iterm2_prompt_command () {
    __iterm2_last_ret_value="$?"

    if [[ -z "${__iterm2_checked_it2ssh_alias:-}" ]]
    then
        __iterm2_checked_it2ssh_alias=1
        __iterm2_drop_stale_it2ssh_alias
    fi

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
    if [ ! -f "${HOME}/.iterm2/it2.4f5d263fc6b8b1a2.py" ]; then
      python3 -c 'import base64,gzip,os,sys,tempfile; d=os.path.expanduser("~/.iterm2"); os.makedirs(d,exist_ok=True); data=gzip.decompress(base64.b64decode(sys.argv[1])); fd,tmp=tempfile.mkstemp(dir=d); os.write(fd,data); os.close(fd); os.replace(tmp,sys.argv[2])' "H4sIAAAAAAACA7V9a3fbRpL2d/6KXnjyCpyQ0MVOdlYOfVaRaUcbW/KR5FzWo0OBBEghAgEOLpY1efPft56qaqBBUrJnZtcfZAJo9KW67lVdePJvu3VZ7E6TbDfOPprVfXWTZ097nuedx8u8is11Uh1cm1maxFll5nlhksu4WB6Yi4sfTJJV8aIIqyTPgl7v55s4M/d5bcIiNmV5sxOhQW5Cc5OXlfmYhPruTrn+9sBUN7GZ5VlUz6q82Cl78yJcxkWwujfxp1VeVCV1U2fJJxPlyzDJTJnPbuPK+KuwuqGezJ9OLg8mF2fHP/apq7AyqyL/lMSlofGp616az8JUhw/M5U1CT5Ls3pRVlCbTYZ6l93aNv9UlL/QuLCIatVh8NF+bil5MMuqC5ljFn6qe9Guk32U4u0myeGDubmJaOx78uYjD9M+GgEevLJdhFpmqiGPjx8tpHEUxYKPz6ZuizsoemkRJSQua3TQTN0fvTkwZFx/j4jkmm9fVLv0XF8Vu/Cmp6BaNszTTcHaLZcV2EVlMb/SmdZJiDRl3U8R/q2NaW1KVcTofEAgN9xDe02hFQvuTEhQA2/tsZu4SAixmcHGXzPHSAbY4oeURaKt8lqfGrwBHHfG74Qsjm6Z70x+YNM4W1c1wVcTz5BMtmZ+Xh72eoX8f9s30nhCsul/FVx+eycU0WQzjLEpoyqvwPs3DSDu5+qDXV73e+5Uu29exaWgF5SF3vfPDjvlh/ObNGf3+rcyzQ/O7nfTAZHk2o63Cxg7M7C4a8OYOTFKGVXVPt/K0HJgiv6O/RBIDgD3J/pCOj3fM8dHp8fiNMfFyVd0b41+cvD45vXxu6pJWOL0nlMgWQ9rRLMkWu8s8SwihLQ6U/V7vZX6X2fkrLdH8ZSV2/mc75uLy5dn7S2OK8I5BU8qTMT8Zn59vPPllx4x/Obk07ZpneRT/QZd+GgKlAfznQOAsnoHosLsZDZyXMeZ1TuhB21saJgbs/DtmBsCQLCJiMEQpRVjcG2CqPnsa/PvXxl/UYRESXRAAaK9LWshhDx0oPjCaVGF6y1gdprT26J6RnkiacJmQqx+A5fR6yRLETvhcxt8+s1dYjv2dl/ZXeVNXSdpcJQsiz+aKMbC5qgpiK81VPSVkmMVl29N987NKlnGvJ7gzMlPvB6/3xFwAxxKGl6BVYJkgU2YpCySCKwFVQCdPaVkD/km4T5gB9pXFd7RWRVkmrzCj3om/pWHGbJAGKSsCjsnnRjEIJHoTpnOBVFnleRSY7+vlih4Q5uaLmGZVtNQarlbEPZ+YY8tLiS++jJf1p8BSwE8yT2ZWzprMgthqSZBbUo8YOGwY1yzMsrzCjKjjWV4UhD+EIhiT+FFgjrQHnkSWG88O5QEdorBiEBE6JHEaMVBmeZ2BpZcCqaD37vzs8uz47M3kp/H5xcnZKQF/v6eUhn049npKECOTF5HvnXn9nhKC3hnTHSYAvf6Frmm+RyaKZymJJGU/yk9MOM0/xrJzwE7CyYqahNgoYepoDThEMfNDPzS0klDY1DIpgcTUvbwgXQqf6/MKqfuCOiRGEvIGkVAiYBf36JGIYFrP57ibQ8owcJ6Z18n3pn56QNLkU7KslwH1/jrO4iKviRNN41lIeMSDLRJCU5ouycK7bCirmoVFkTDxxoY2ZVVXRK4ikpLZDbaQujAEhwVkULBA7xDthMIloy3Wcw3EC4HJwsa4i/5znp+y3yHaMZnQKNRlmt8x/KgFJB6YRZpS32AJYK2AL0vURQJKoWkky2VMDL6iuc3SOCwMCTPikFAt6Gk+/ZjQggm9pvmiLhW0Qe/t0S+TV+dHb8eTN+PT15c/0C4ffPOt+bPZ3zt4pv/RsGfE26Fw0CQJvLrz2KKuNBlACArzJD6S10BLgt9HFm7E19P7wJzM7aqwz7yukjY+GtqugBGMGwMjc68zGmuVZyV3FMcFiUBAChvCSFHWxTzEBDNdtNI79U+AnxLe3QI/CBQQ3wbMhMaffRSV5t34nXn279+Y2zhelXRfscmXHQ5TkuflHc2SJJeSG/ELsIKqSIfHfVV7opjYeExYGROMo5wAcHp2CbYBpi86RxKlsbkLE9H3cCcjlUfIh3Q3Be5waELq3RV35trKu+FwnmMm1w66QrmgngnucXUXE+8RdYCI/+jXN2dHLyfnY/pzefJ2LHT+dA/0e1nUMZA4Fb2Klb/qhrEQpEvAjkjbJJ1hwt0FrKmQ2kiKFMlZsCNpXbLCgy4g36jjVU6IP02xw6RyEDAtHotAJ66b0WwLgBFLY3lJLUpQm05AphUqY0mwMmoKbKEOA3plQmKJ1FxDGt3sVuXEPA0XKhmquqApEg2Am4IbE8gxRFxZ7Yz1OJ0h8W3pWpeKHZC9p3fubu6xVqAQLjOSxXF0yOvBG0b0ZBXu3GmV1zQtVlmIaVDPsiiRWoxwusq1OdC0gt4EnQIsI/OKMI9kZi+K587kfIjggZlDuxtY6htNPU9VnEWaT4ld2H74XjKnGYIkQqJiX9+B/lXoS/hnqW9kfwVxBkXH9+pqPvwLMX20UhwdyQRIgRcdIFiRoux7L048Vk7tGH15CZK+EtLBHk1jEGILQkUf0TQa9ABnFQjlU1YHjAdhqevytGPBlLuYbSNVJYiXgNCI8u8KIhEWuYLD/JIDYtAA3yMsbSEBCAdoRDTv64K/tlCRFc1hs6TOOw/sG5jMJP4UzirdN1IPIuoR/H90SuihG/AEXPHaPrkGCwSDC4jsSeJnyczv8w3awuWqD3wD21fz7ucfzt6MmZ+aJdtYSZaUN8A/KKJ2gJhsKWF6pNpYwQKqx6yndUR3IXTBv1UKMa2EpoQoIjtmdpvGVmUBqzTQSKvKItkTCIO4GPIQzOnQTRGYn0WdMWGzctluViWJ7c1qUnyyqpF9YJmQuD6brgRmoo0dHUJ3g9dKMg6Sj4iZFN6YjRXL6a10TjDcYo0vMg2XfUGG2U2dEQMZmQ9XfN2CZGQyviMY1t5/YfbabSfKahYF7kCgwa62DfBPgTtqmw43drfzAvWq73w3ckez/4owKS0AAwWb71kCZuA0Q8WfZsyyvO4QiuOVfVvGa9swXGjK3A5b6jcQ6Lurx4q5bXeWwoIZFt0uy4C2l0jF56u2qxa+wxFzEOe5dkY8LvgtT/QRLKuWxFrW2BAUjHYXXW5CEVqKZSR2VnVBsio+fABNeD+LJTRWqCHarViYaG61eH9dNvct4UC1iSMW8qpNsvBnIgXgWJcNunx1g2N807c8XNvQvLo45gB70IJcGPRI3/qwJ/itGvXI8u06czi3Nt0//Oaqb1+gcfWdF2ZdV2ynEK9IlhMOko5w2Cj4oor5282EryJFzdLq5aQPM0Do1eCvmWe+0qb9zyxUsVAab0BFBSUhj4MXjQisszS5jRtVzNmlwQP663PSn+ssWme8MNEaNkiydkE8w9IgDLlNzggkvOMRprGwUnDsmG0ExnCH/Q6V/eoI1nIqCTlTi65qOoGHW07AevhAOD8vA7vyXctnw6Lq6xzEr6Uorto0qUFYZcNKeOEiOaqccNs0Jgv9WpBZQjpoCbErzIMQC1vJnTZ9jDbl2tdmm566KZZbBWWDRqzx0YhW+0NwB4i2qozf5ZgDcyk/xsDTgTm74B/9L8NqS9yAgagYX0VDtmEFh6y68FmkbpfVku66dtGBwzb2zapEO29Zry6o++YqLEtLNnboL+QoXYrSl5ULWz8uKeZ/j/2GCZf3ZSDeVTuI6OPtPXaTRVYnjD/FMzGjxYie57l58f+G18xSN/oM5iSas5xwiCViaY4qIpRpXcW8cNCdOgR1lCQbqotK39AufwrTOlY0YDcTuxb03XmYpDWMXYUndZvdA82pEYnhZRySreFBtCgMvGCLTklggQOlDEjMTrrQ2rKgDZ6HhsEsT+tlBoMLV8DvsoPf3eU3GD1w1tff2OS9gdmzVkY4jyc0v9ld1G7hK5rSaV69AvGPBfdJM7fEAjQCQ7jLCzaxowROrJx42F0IW3qZf4yjLfDQwQUePF7vMczV5vBktjMVx/JWZFuG92CrjHD+Jor1oSx2ofV8E0e0W2rawu+54kaDFPTU4sWDq3Q22M750X1z0XGTK2mn1swg44rxtBTb8iaE9y28JSILIRThoQYUynqGNc3rlK0iFkr8wy4FGhE1umHng6J+Ag8PXDM2HEJ/b9k/0/raZ3lW1uKNpgERPCEgQhcvckxilYBZsAL1xNDoKWIxtxpMUhFbVvnKwCcFWXxx8vrdybuxOGnEY4g+gO3PYci1sw11mmxih9amBybSDHxiGwOzbevhjchT9tSI0zQqctJJWXJKQzLD6zKcpvGkVNCO4DvwrcrJcJsU4Z0vzxtm2KDiubog2MlS5WIvLXJxKxV5JSC5CYslZCYcRjoHXhYvZChT0DX2B5Ycse2W6pptIVBbM1osJoZpF6LbuBK/H4jTNOBl+R07d7PRPK3LG8deWYNUEEaRn0QKmE0+1ljcFve/ZzR5RzusCH/cxFHOoRStYz8czw5qmV3VnYQNh+Is3YaehJml3fE72JvhHTEJcdm2nbPUmS0j8/9ZGzbD2d41Yy9t8YJ6+VtNCjywiv3N6sY08GIojuV1YV6dnF9cCpb03c4v4QwXXAWu8a7RVmeNg5/0DRprnVShiDHXuYPZh0Et0J2+LabexHVBC01m6kMW9c4qhwmP7AmlSCcDxj0HFz3IFxJDpOw6/RPVzkjFY1WHiFhc4QOlOev8kMDCwPHCWTAR0kN3QmgVTqVgOzf755miy7KY6+9ukflrfe46YlFYFGKYQ0YrHcHpn0lp/P3Ry1ek4eVLcw29pBlmKNs/BIsJzKXyl+38yuFWTv+Wb2E3Bg7DIA2SfYshwiDqwx8u8jwyLlMGnIXk63IDuC09sqWUZOtUq3xN9V2yJkpC9oaZXUCfBVB3da12GbxKBAZgIAPxiewIUcJFlgMDy3VN7oBVuW18SAQkqdbKhOwU/gWMYEUX4vE8nuVFpOKRpG/I3lkNNCLtoMjZx2RW9TSF44y3qlrWnzRBYMACVB2rdQmP5Ar8Cb5uumi6lAjkoflPWu9ELibf3cSfWFdEdzaHgOD5gkTKrHn6Xxdnpy8C8yM2XbTKJGMpTNfMGy7p9eNmqjvE6CKaWEX84OTy4Fi6Ve+nLixcrYTV4XWaEI3N8Uv0dHaX0XpvklVQIgdh4GRccAAxLmAaiooLFZ0J9vLt+18mSAY5fnMyPr2cnL27PDk7nbw7H786+YVW47nL9jaan4+Pz87Jujt6jbazCeK/b8PiFjKqrIbyXsmBsdIuZZYvp3QdEdeFVazhN5Fz99YVOeX8ljlnCbAV/gRqxd1Q9kh71OnrXN6cnI6diQOE/KCdk4QzYn4Z+2XZmGKFRPZE38rTSAMQqzCzcHp3RCNcjC8Qct0yHB7rU6vRoucJr3MSFguSWAQNNVgniDEMuPsBtxt5+Gs9/p7ncTINE2Gmc0yyj7SfgIDEKtaQtJQ9V5xWUAnfZs+pkKi7WFnnNSZxTdbvbcLqig11F+r+5EkShfP7JKjhlfeee8Yuiboj1OLAtc3cwGYTZ0QODeeP2O2FlClqhO55VTJvzsURGxmuOUIYxGfvRepX4dTMSI6FM4RTDmX+HIkTrge8LuBmCWe3ZRoSpcck01aCb6HTKzgruy74Xpv9s1M24ODIECvY6ktXtatgZ4smXbX5INQS8QyaWQ3LnvtdpXCywN/OiEPgcngON2ddvoScoNW1Oyh8YLgksmy3E+OKq0X9PKF5efLq1fic8Lq7k/lHzgwpmVuXBIV2pmr92jwVwN0OKxiRa8g6ix1YYKogOQSwzPekqRjEDiGJYvPkd201SaI/jE+A7pA7x+Wk6y1Q7rfYQNhCiBMfUofKYrTNH2Kk2LmcHr0dDxwcFv2EkIv0Cw6SRyLI/7Qnaw2ZG8vmINDLvjjcUqPVU7/hfAkHvvfXSn3QHx7gJwPjNTNEN3947h3dugm2jp5sOPb5n9Nckie0DweQ3pVIRiIrjl1gf6nN8AK6m8szPBfa6Gb4iv7SYgYgS/rjskp+vvCuWveQ6xPisb6mweRFZNSl4f1QJTW/u+K/lae8anN5j/PGrwHftXW6jifMQLkl4UIZT5hnKqwKkfK+CImWNV6yji4aAAk0K/YV/zT2BPXKkhcnVnakP/KLOKxWlJXyhHcYv+wKKRVP+XZeDvqWedgkHSYzhGYroQDVDhCnrpLUIXgiGkUcA8RRv7B2xrwFvhYbTWaPC1Ga9moXXBC/Q9oMCL9L9Nb2ZMs4Id0Nvvpudk1C5ACvFycwcbfLMAWvjNl5qNLgsJ1VwhpKUuaa1daEPOCZYPNMdY78tl7ZbAgJt8VpOtSu84yjdZ8qbEpSdSnSgmcSgjJ//8Pq0Y6SBTeENGOv8+BxHir5C+1OWA5je9/oekMhkCwDB5MUewX72klunahCLkpmlYgHIiFnCmzU4LWNUSGZRT9RHWTQ5DzMbHwhisXlqHwcAJeYZaZoGxA1JxXrSn6/E9/kCEZZkUJYQr3yv4CGvf66z7mzFOkR4/loPDD7/Q/7VwGE7motEop9SrI6/uyEtmh2W6fCqXLl5iQ2ArCIQUrjvvnOPNsMwm5MjcVNCDRz2TxdaQrcSAentQ7sz4P259OrTk9PzJjzYGGWTpH2YnxSrxSIaq1yrIh2n/FB0skyUBmnGQIZinhONpU4PdZ6l5AXGNtQEbZAeh/9Fb8BJ6eCJqyqEDwGoRcj8w0Tui7m2dUWgHWo6gNAddUC5dn68o/gtGA3yxbhafzO2g0brmWz9rnNG7vNaOZrHYuOx9wunMGyjCNrYmecNJrMiHT2iCB/IwZZbqy7M48RKQV73hdix0YYZ42PNTCBFa5o00VMNYVby/fL+tv7LFFxBHUbYT1k8a3R1UafolMMkBizGpiPmLClOhiXCZ76nnEIz7bh/ze4wZpVx/v1tzqvOAlRXlW3CkLKiN+yKlsXVjLCEBiYaS3a/crp2HaT3cMjCGkbltobmRPZInZwQPGeB2S0P+Bx+PrD3hXwYcfbce4N9+3NLsA6q/2wf0jt1vfDAuLBDWlt6s/txgbmsdQZSYQ4gD/rJv7kC3A/YIGf2furfhDFm9lhrd+JZdmIM8wDuJNLfwNRu2MLHLYN7a5yc9yNqKfvuoXeZwlav+R31j1ED9GCkysnCxmwVO4fbllj2dCYXKvL7FRURlU+WHN8LjDnvOYqidlrx2c6xNQqNLXDSmr24Qre8TMWICXnPvsOicNTeD9Kw+U0IlPm0PjDDv2TeMmaJLxLiIc57UblWFsdfUVz8h5xb5gzMQ7zko0m7dmastAAVa3p6NOZBlStBarRC8BDzd071nizEpn8XtaEeltrG9QvWg6mzzyf5uPRBO9U8Z2JIp+0Ywe6D0PeANaSrZqJzMEceV01/RHf7aCb9Mn8VwzpMsYJqq7WZV3kNLDEPGO795rCAf8F2xIbjgBJuOBcRqQ10oT9g72Db4d7/zE8+Iu6R5/0rBQkTOQwEG09a/6ZuySxFBhBSvZ+EfdiD8SiyOuVTTmNJXxQ8pkkwkDte05TZF9IR9vnVFtrE4jzqNUjWgtdjolpnHWRZ+rSV7PRSvmWZBSJA6zD7+LsHkvVjnaAqLCf9cE5O8pjjODXfict7ENDiFcs98VjpCQDToprbXPlOtvgqq8ZuL4g4WSVRIoEIzkEE/BF15hkLMDGlregBvOG2MengauWo68dca+0YyDpN68XN2YX0QgH1yxGSv4zeuCQUDivYlFiVosijGDEMpVFmoKeih1oqQ1ptEJJ5QoxWktfYkrosZHAjFONIPFxhsy8O7r8Qe4OwJlYb9JlQOxIFjMUQI7ccq6z/0O+BPe62ynFwmcP8y7Jjt0bfYJTj4zgOkJ/oIxFIeNABdlKJXNGEdpVUXOUrrHF1MMYimmVQRnO07qKeTKBk1KCBAx2ssuJjDnyFQJrLCZz0+5xkJRRsiDF3031+QRx6PHm7H5V7tI1knXal1wBkZdByCE6n5oNcPnL5OzH/tYUSGqhJheyxkay7746cO3c+OFm6hruuilujy9hPedyLROhrFMYyu0praCoM/+DtxK/T46/8MmOGldOO9zVA64qNyOJ8xtGTveIOfMhP2Id7v2X459O379580VdJtm2N23+3OjASVilqbMUxjpttkVXV6B1KRF5/Y5+aTWHJl/GGfOi+flAHoabh0iYwGiZlISmPqYkh5ZahMG9bRijneFxb71zBLF+JonEXKsJ/ERrni/DhxHlPSIgyd2y50zUS8enPPy+mksaq3hzdvbj+3eTV0cnb96fj20emsMoHxzSf9DN5gSitqsZqk8QM/icq+2IGxITJwkFTmTPI+/ix+nZ6fFY4rFrDNhyWHr2d2Z5S+sVEW4r7I3jCfeimXF7CWd3/WM3nLIsM+f3HG7m+pqVZUOF44xLdi9DixAlEJO0mpDrchdbVaFVxGlYZzMcpBIxzU4zZditDiQ+eHGthffciPMbkPNDUj0wF7noAQyR4fGxE+gUkSCxzrhsIwEi0dEln+SVgzmtgqYuJd3G0uoWzUFlSS/Oc4meFXpMShVGixp3ojg+5OlEuMhisEUG19lXSKd2b5f2SLc9nynqnJ6xiYUiWu8Gji1Z0D1vgw4SuKn4lB/DDNFH9jfDn8Gn06AlrQU/WLpnH5MizziwhbEUY23yz4crK5kqe56KtyMvGom1FpbjJPWW3ATGDYORLXA6gjHrbFGrWE4hWDmbwEpFliWMa7SHUSLNRN8WUITmLo4WcaNGNB5bWMCq03JuDAEEmeLAECY5YcV9PSUvwGzdvdRQhVGsm6KEjJEU40qXHxxignBBZQs+1dxSpUORVjlpdCelRSE5m5jPXjPBxXDG/l2rgNuO3ICenBjs+pgZdJy1qVvNeqkHttkKb14nNdxg5nqk5In5E14Aunvf6ZohJV4MvlNYk4TlC51J9MKzR0OrG6ZvqSzANEwMXHvlZZb2QBv1zpskDjDniNWbo4tLU93l6mgLeh03KCZu3aCDdk1d7+fTh5bmxJqgPQ00OKYuvcPhwVUHSk7zh3rUiPQWwaSSutEcRxtavA7rjuq030hy3i78+JAZU4v3r2lWXc/fZ6P723CM3exQWzzSoNul9Luq0z+ueT2sWXUn3dWy/jkt6UEoK/d5GMps/AqBSOoOtyf+mN6hsoa6fCG+1tMYYCWrJ1jkoVYFsMlY2r2kDCbd8JmwY/G169gxfANqFknaKkysshHmTd0OrVQwaA+CCLUze+PEITJOdsgsInWi39jLqrLK8qGvmn8bkU0sgrha02hVbf3fgS9HMTmPQRgstCCIuoGYoJKLmmd/j4ucU/cCPTxDmodk5DDXtplCjsH5xMk/cQ5Dwc1l0/L+1CA4cbjbWPVAThDUIYWdT2nLsJHYBeu5YTkHe/pOkjhbb1ajaOAWzv8mcVsjpKmQwaiDLOWhsTmK9ngXL443eUkD4vhwkyrKNXcAWFXVnFCfRzY08J5QMRctEaTXGvm9Tg5lHLWOGQ5kFxxBZQ+0xm6qNm8FK1pkSPh3DYOHA+BfagHZZGaVhpMqnyRwPR74hKSkISBJp9XvNSvXKkHifWoaKoFyNKUMGgVIOZyWhulj932xS/gQTZsn1HaUlG0QmYnWQx8ew8vjbjzNMaFdjVvNn70n1lurR0Ua+kssea/CpNA0sS2q+E4pE5VQvWSU0ZQ1DOUIPIMYu+gTeXuMv1nE88f0xOZUIeGW6IyuwiHHmVpwjNztaW67O9S4N/SA+iMHeZq31LCACjdq74rcERh3PGwyKV9e6PrHteYPTpKLb85DcZCeHPjWLD539VwGQ9NklTHM8tW94A+RR7goYoRipnw6Tgw4HL8VBUcy/qh3nESbCa8SLT0vUMvifDz+ZXw8ef3+6PzlBJlAmm43kQfjl15zZhQTYMnbwnKAvVJpTHPu2rZN9hgf8OdD6lrjpGF0dJ8VbHZJ2Zx/W8CB27KXVFG+cWF3Ldt3vz5gzbIdm4kN8JhOLPjArJpVXQKuOmm5IgwmKPVyJLWjtdMzcFPlZ7w1bAvNnKRTJ5tBPXb8upSFOLm8cGdTrxD1kUMV3go55ZJZxlVEnHbYVdiEWWOPsVEn52tXWsxI02zAxAPzk1MOyOkoFHU30+6aCj4K8DON73bch+KfnyfWZmQTuhzYk9xSVYI9rU1aHPOHDsmq8rtGRrTkjurbqb8ADGOSwWbATdpxG+Hn424mwk4eZQPfv9Qb6LiqkDnJdMDDwuG+8cSSRf/xM94b+uFjp87WT++2IADAPweDRghWNx2KVthKCbIODZ+L2FNLU88DsBy4xjvXDaFe4+XrVobZLC0+mQj9MW69yoSnaTRBeb8RRwh9DNl98mFjjxAr9PbtaeQLPbTDuB5LQT5bR866fhq/uehQHCkdWNETrlbB2pCeMBLvimt56Llkl4GNOOHesY0IDz2tUOhtYksubT/GvtPJwHzoXGGgK/M1p3f6gCGZLM2UHj/cp5n6a8rIVmnX7OcbJHFuqC4S37f1X/jciUT5nFw5m/Nx2Kon8rivwdY1HcVuNoT1RA7/ukd188LVXrL2onQXuI1FsGKzUUzhUUbRtZy3xq9ZDxjZ4hDynz34fPRq8v4UOap6DTfq5OLyfHz0tv+Zs8YKaiHMBw4ag9evlb7oAM37qjw0X5WIq+ja4v7n82NkeBgN/tZcmK2nnDsnnR+EVUe/6WpHHcWpXYWet4wSllxazJLz4IFmbik7OQZuvTPw61WcXcyH6Dmd0hynYU3W3jEp6NTru7ysLvM8fV82h8c5liUJ7qGWGKuohZqEmhwtddYWWtBMdE+pD6jaJ1+gwFy4Qsv9b83b5PsBJ1pqsTakVqK2w8Xly5PTyfe/Xo4vUCfOKQDWk7oJzAw/hkUCrlGqgy1vyn8eIYk6ze/AA4R9sXQl0jx8SBNEKVQ+sYHZSLLBjFR0apGEKBdZ4aRfyfIXKOMecs1Q7a1ExiLeySVXTLni23DW2FgoJrdaaWIQVw2Q9PaStbQwigr00KSQo4CbmNWDNl/ZGFsSqtXbFPQSZBF3vPQlpaqoj/H52yZJ8uQl+nDyK2yWpmhfczn9hee/5VMVAdzLfxM2nfyXg8ZDnEW1fuD/Jrglv9kCqeGCncjshBdpYh0h3BWHTt6fXI7brtRCVYtWOU/TmLRRd1xt7KrCcj5oQ+3rHREJ/Dx+ORmf/sRSDwiljlMyQjvOrTUw4ZasGb+aKdsLkmvWcmVci1nAWLTyNxT3BiHhcK6nAB2h3jW1IyF/JJmVosxCg8yXSVWtpT9zEy5Kao8jiHVJOAX6rIC5Hpcg8kR39zBI1figvEaEKFP5HeMdgho0eYjTFrjSWWY2AQfBoA/plT96HWKkJVl3t8RWLOuQsiVspLK3DxqNVKrgSx7z6PTXxlkuThU4+3tPbMBJqS3KNcC0ggcAWT6l5YD5vEKuQuZ49fn4pHMeW1xqpRmfvTI+ny2fFcmqYo8aYn03YQESHvABx3xR2PORUo0PdhFO17LLzB4sDSPf1i3hik+2sB9Il+sUOGTO2fH3cPV0qjICI67Zw8mJ+8y6aTblLjVa3U/wO1iJZ2mZLyWQkOD8HHyFZHzmJCyA8WEa9IRtHp+dXrx/e3L6mn69fXt0+lJQXsqZDZkyh6BMb9C3O4jLZgNgnDD5ssmDXBeOucATR9bcRRyzc2xCFFrhiOfRa+TG/XB29qMdDxJ2czQ7lrynGR7NodS5G8GzYQY4PztngpzT6XEfOReVOUCqlwgwLooa6WqaIgClOZDN0Zgbl8+BHsMSjLOjSC4WIWMiE9aBho0Ya+CbNSi8wpVRbVxLTlcJt/KCniYItm7P/UaNZJjyCRxRRjs8oSWaQ8eb1ZxRs9kmEiJrMlnVtG+omUFp30n4eMrHjollH7opnN7Q+1wGYnvahd/ekg7ANQjCrConTIhrK/z5Jlbm1XFP7DRH7piC3NqdzLWES6yxqk1AYqUPIbw9RtziqT/jFPgtWyDoWIljWT1yHD/XFIUmkeEaXVxbv4n4/veaxIZW4gUtSUn9Si3Qo0oZN9wRN/wwJRxLjVavsyE04eo4BMYU2JQcb842qpSkOatspV++dSPaki4DJEMmfLDOoZye7rTSVL85fKbedQsOHk0420ZN0y5LYHxksB1w58IIpYESm5+UZR2b/acHT7/tg/+vpBCRHY3rahLix3P4z5xzOkyBi8aDJ4BR+BH8A3OmnlP1q9/queWkMJY9uR6SZBtBwtOwycM2q9N0sTFqCyuGkWD/RLHYHnFv0IzV9B1bjdYpAyqKKdckZ5/lqeuXaxHoY34bN+en26JaVqA2x7Caav5mg/teN+noApGjTLQnEk6oKeb4Dh3A47hOEeKszuGD3aIEU8TBLd1sSRBwRGJNXCVlzOfAEysxJIID8z4D7LS0iIpx5XSxVLhx3G2mTJYrzcTTAnq2OqjjV5sJpYlssW8+wiee03Ril4OtRd3XXFVrlR1yW5kp6BYA+t/1S3UmoVWlRyAKGrJo6r548sQb2DItzStc03qkbwass6yZWP1/3WuGQT7rJUMjpRrhrfJG66iwofRH8rwaOm5f2og10OOtwchOTL27VZ0Ca9T3X+uDvf3/4AqmkZtoq5XunePRXbulTQ/3tmUVes7ROLHHnbFYf9di3k6mdg66Ccy7WrPNNZX1gQHkMxRkpqPYOwq9OT4SYjGPrHpjZTY5pwzvH1xldz3bpyTJOl+2zM6EFW26ylWneOLWwBbicZKEeKh8tkgWN1Unp1hW2IrSmyYX3c0OlJr7NnHNF3mqVQ3ApvCNk5P2GyfOaXERqjavvUn0j63kbDHcCQ22yetwdOO+TWhZz8mwqYeta7/zRrvLLZnYcqe/i7vvsPvGwMY0D7eOxdmNkv/xRyeasM3J2MEq/awAe7T1UxBbvy5jfLsmQIKN2P6XYMP2osn/RORyLXq5vYCubsdDUTsNHYTTkh9NJgghTCZ9N6lm43znpitVsEUD3bEtg5CjhlqhMTfrSNZUlOet714XKwaW2FHBlt7FdSiSFGluHKiScuH3bXFyazI3vdOOkcoQfLlvVHbOCYnA4Q+968P+4dXDcGmJ3A13mGN2QSLIVlqPD8IVjo8ELTthuq1T/SfwQ8Xjj/H9NA+LCGRfFPWq2pB6+0/3Hg+Fr8uadXvS+F+VfSnR2UziS5jiF8TRN137Tty8naHtCVUOxV6wH8yBhO4W2NSiwWma41x500X7hZBDs/7pjza5q2E6Mo32PjCEbneQpX06u4vw0C0S6TzFBLfwMXj3NIWtbSuKm+3MqnHuULR0eswQaO8CFHSXPyHU3qXh6OY2Z6CD5tL+D1ts3XXUu+E2uNlhhLLP/FBi6seq0EpidtwJR4Miylwog3uz4ky8b2Ij2Kwe1sHZyJVPYIm6XsjRuSYdzDXs3Y3ou2X7HLuHGeOmMSQVtZKsy2Y7Lz7IbxmvPnjcmqOI8tmgYPrtM/0mQKej9kxmWM6SRJG+Kx3Wv1/AwBrI+dCoXq5Knwftb4sUrsWVuoTc6jLEBivEl4SGv4h2/yHu0tRDhbNIvv0B3bR0U7BJXMxA4OlzBGmqvLDp+qR9h0gTtV834NzDNk9QDhhqp7cJcs6dpDbIFETjFZ1ITosAkvykm5pxq2gLOLefTkBqHadt11liF4dvc9iqzPP2Wxo+/s9qMmpko1x84y8zBPKfr1fyNY+BaS8nL1+96W9bEEJlZISkLiraDyYcbhz7bz76YdP15EQiU4/9WIhvP1nStx/TGA4NF5vDA6kPOVzrmR3T9nMd3YqF8K/KNSvwnAuj1Klf55A0r3yjUxKyWYVvdDlfA+GaoihADTnk80fKGPCa/j6cp6IYM5Rp6NsEH51aB4QClBVpRiWbNhjaL6U5INIyDXp+vfmyBg6yB1uM44eDvU+c4tqcOMShtjSegzeS+VFU2z9Y1HzF5YZLvYt2/Vw+RLQ2QFI1gUtZyI5sB7uEbaaefnBHDiB24gudYf329I1bSZH9Z/aALpe3tI6QnVIJ1Pn0TTcdKUyJc/eDf6Dc9lYGJ0v7B2py9z5LaQ2p9nvKvRJUxUAVCvWTleHdhP2pI6egplZLdW/J2lGLtZ1It6y3rbLufFjBpV75uMCGjiXDxeHtZtvRSL+8d7iuiUMGORV1m1rJ61V1u4Pompp6sg9PIU7XJjE+P/+ySXAO7//FJPA5tbUki3bnNnrbmhaRT3/r1lewfrkH6yM4Cn5bntRut415fCT0j7geJafS2BDIFKVQtJxnuKVHLvRHwmMaF7tSPG83q9O0f2igBTaaDurXrtVo3+jMxWqIJRpbNEncI01yr99fS0KlFlqhQfy5e9vSRDplIS7vV1urQWynqu6OWj1Ndr9bmHi9QqutWOmWaXbKafsP1CnG9+3WK8+yJ7j50shc6xNfayWgtrB2YN4mojStFc/Gx2GlELQ7Z3GubeovnLFPekjzBTJVeAeSZMmoun/wl6+1S3//qcMyN1OI/mXu+JnspDUT+Iu7s+rds/0HXBqdrh9PYHMPOik1u5DmTyhKtkRV2EKQ7TFF/YpoyIcENNlePwQJiSlnVWwwxjkAxh+3FY8haiSmcRW3Cea+PRmI6m8DVixJgv6WTwdSNdvZs4e06m4FdR0CaTJf6DNsjsErVaknesLieYYKxJFWIZ5oaXFbdli/hMp3kWzkfqTXRDWr1m4uCko2gKD4C4NbS9Rrx05V4k2C6rN3RolQ2CLPwNwkWumTlMOhW4GcVUarykMHlINJREArmiRxA+ONGXFYwdD6eqSlBUFg1qqfewaoETtncIAAC/tlGQ2NWqVPbIlIVV5UfZDa5pzJghVI8SzCHHx28RWvgh0eChZaiD2qpOqWtVbi9lMYqzyRzAAz54DTbhR/ZN7efLZNwa5gks8ei/IVWIAje0FAV/G5YlvjX3VV3ekon5VBv4mt27BPZjpKQSub+499IEUiROvV6h+sOv94LemHpXBJ1uvqAJ4GZKjgf4IPwMNOtrPJz+dnp29+7Q+aCW184OMzQaDBmsDsP5Do2OvBqOIA62TCQZfJBPgymWjMpTN/lW+CUF9oCkPAWYNO9i0LC5zBIrQhBLAsQpFUA/CSwbP25UfYRBLs16i7tTzYzClNY0taR6gkt5Vi+87CGubTxkwDM4ZUCgXlG4egI0NDyTMcNqYwf1dZcsGdLwTDHyGFfxpqlJiExs33g3U42rEe4Wo9W+cchOlvpkh0XD393v8Aw9aymD9+AAA=" "${HOME}/.iterm2/it2.4f5d263fc6b8b1a2.py" || return 1
    fi
    command python3 "${HOME}/.iterm2/it2.4f5d263fc6b8b1a2.py" "$@"
  }
  export -f it2 2> /dev/null
fi
