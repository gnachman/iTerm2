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
if [[ "$ITERM_ENABLE_SHELL_INTEGRATION_WITH_TMUX""$TERM" != screen && "$ITERM_ENABLE_SHELL_INTEGRATION_WITH_TMUX""$TERM" != tmux-256color && "$ITERM_SHELL_INTEGRATION_INSTALLED" = "" && "$-" == *i* && "$TERM" != linux && "$TERM" != dumb ]]; then

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
  iterm2_begin_osc
  printf "1337;SetUserVar=%s=%s" "$1" $(printf "%s" "$2" | base64 | tr -d '\n')
  iterm2_end_osc
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
  printf "1337;ShellIntegrationVersion=22;shell=bash"
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



# it2 CLI over iTerm2 SSH integration: unless it2 already exists, define it as a
# function that materializes the embedded copy on first use (named by content hash,
# so a shipped update replaces a stale one). Needs python3; it2.py reads
# IT2_SOCK/IT2_NONCE from the environment set by SSH integration.
if ! command -v it2 > /dev/null 2>&1; then
  it2() {
    command -v python3 > /dev/null 2>&1 || { printf 'it2: python3 is required\n' >&2; return 1; }
    if [ ! -f "${HOME}/.iterm2/it2.2e1a7f98b497171c.py" ]; then
      python3 -c 'import base64,glob,gzip,os,sys,tempfile; d=os.path.expanduser("~/.iterm2"); os.makedirs(d,exist_ok=True); data=gzip.decompress(base64.b64decode(sys.argv[1])); fd,tmp=tempfile.mkstemp(dir=d); os.write(fd,data); os.close(fd); os.replace(tmp,sys.argv[2]); [os.remove(f) for f in glob.glob(os.path.join(d,"it2*.py")) if f!=sys.argv[2]]' "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" "${HOME}/.iterm2/it2.2e1a7f98b497171c.py" || return 1
    fi
    command python3 "${HOME}/.iterm2/it2.2e1a7f98b497171c.py" "$@"
  }
  export -f it2 2> /dev/null
fi
