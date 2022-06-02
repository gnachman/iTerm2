# This file can get sourced with aliases enabled. To avoid alias expansion
# we quote everything that can be quoted. Some aliases will still break us
# though.

# Don't use [[ -v ... ]] because it doesn't work in zsh < 5.4.
if [[ -n "${IT2_ORIG_ZDOTDIR+X}" ]]; then
    # Normally ZDOTDIR shouldn't be exported but it was in the environment
    # so we export it.
    'builtin' 'export' ZDOTDIR="$IT2_ORIG_ZDOTDIR"
    'builtin' 'unset' 'IT2_ORIG_ZDOTDIR'
else
    'builtin' 'unset' 'ZDOTDIR'
fi

# Use try-always to have the right error code.
{
    # Zsh treats empty $ZDOTDIR as if it was "/". We do the same.
    #
    # Source the user's zshenv before sourcing iterm2_shell_integration.zsh because the former
    # might set fpath and other things without which iterm2_shell_integration.zsh won't work.
    #
    # Use typeset in case we are in a function with warn_create_global in
    # effect. Unlikely but better safe than sorry.
    'builtin' 'typeset' _it2_file=${ZDOTDIR-~}"/.zshenv"
    # Zsh ignores unreadable rc files. We do the same.
    # Zsh ignores rc files that are directories, and so does source.
    [[ ! -r "$_it2_file" ]] || 'builtin' 'source' '--' "$_it2_file"
} always {
    if [[ -o 'interactive' && -n "${ITERM_SHELL_INTEGRATION_INSTALLED-}" ]]; then
        # ${(%):-%x} is the path to the current file.
        # On top of it we add :A:h to get the directory.
        'builtin' 'typeset' _it2_file="${${(%):-%x}:A:h}"/iterm2_shell_integration.zsh
        if [[ -r "$_it2_file" ]]; then
            'builtin' 'autoload' '-Uz' '--' "$_it2_file"
            "${_it2_file:t}"
            'builtin' 'unfunction' '--' "${_it2_file:t}"
        fi
    fi
    'builtin' 'unset' '_it2_file'
}
