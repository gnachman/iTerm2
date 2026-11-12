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
    if [ ! -f "${HOME}/.iterm2/it2.360a8dc76dd1793c.py" ]; then
      python3 -c 'import base64,gzip,os,sys,tempfile; d=os.path.expanduser("~/.iterm2"); os.makedirs(d,exist_ok=True); data=gzip.decompress(base64.b64decode(sys.argv[1])); fd,tmp=tempfile.mkstemp(dir=d); os.write(fd,data); os.close(fd); os.replace(tmp,sys.argv[2])' "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" "${HOME}/.iterm2/it2.360a8dc76dd1793c.py" || return 1
    fi
    command python3 "${HOME}/.iterm2/it2.360a8dc76dd1793c.py" "$@"
  }
  export -f it2 2> /dev/null
fi
