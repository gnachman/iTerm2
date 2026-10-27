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
    if [ ! -f "${HOME}/.iterm2/it2.aba20b206c1e89e3.py" ]; then
      python3 -c 'import base64,gzip,os,sys,tempfile; d=os.path.expanduser("~/.iterm2"); os.makedirs(d,exist_ok=True); data=gzip.decompress(base64.b64decode(sys.argv[1])); fd,tmp=tempfile.mkstemp(dir=d); os.write(fd,data); os.close(fd); os.replace(tmp,sys.argv[2])' "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" "${HOME}/.iterm2/it2.aba20b206c1e89e3.py" || return 1
    fi
    command python3 "${HOME}/.iterm2/it2.aba20b206c1e89e3.py" "$@"
  }
  export -f it2 2> /dev/null
fi
