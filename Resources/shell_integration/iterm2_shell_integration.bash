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
# Guarded on the directory existing, so a host iTerm2 never uploaded to keeps a clean PATH, and
# on absence from PATH, so re-sourcing does not stack duplicates.
case ":${PATH}:" in
  *":${HOME}/.iterm2/bin:"*) ;;
  *) [ -d "${HOME}/.iterm2/bin" ] && PATH="${HOME}/.iterm2/bin:${PATH}" && export PATH ;;
esac

# it2 CLI over iTerm2 SSH integration: unless it2 already exists, define it as a
# function that materializes the embedded copy on first use (named by content hash,
# so a shipped update replaces a stale one). Needs python3; it2.py reads
# IT2_SOCK/IT2_NONCE from the environment set by SSH integration.
if ! command -v it2 > /dev/null 2>&1; then
  it2() {
    command -v python3 > /dev/null 2>&1 || { printf 'it2: python3 is required\n' >&2; return 1; }
    if [ ! -f "${HOME}/.iterm2/it2.9ec2bce60a6b86bf.py" ]; then
      python3 -c 'import base64,gzip,os,sys,tempfile; d=os.path.expanduser("~/.iterm2"); os.makedirs(d,exist_ok=True); data=gzip.decompress(base64.b64decode(sys.argv[1])); fd,tmp=tempfile.mkstemp(dir=d); os.write(fd,data); os.close(fd); os.replace(tmp,sys.argv[2])' "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" "${HOME}/.iterm2/it2.9ec2bce60a6b86bf.py" || return 1
    fi
    command python3 "${HOME}/.iterm2/it2.9ec2bce60a6b86bf.py" "$@"
  }
  export -f it2 2> /dev/null
fi
