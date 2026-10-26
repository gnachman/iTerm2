# Restore ZDOTDIR to its original value (typically empty since macOS doesn't set it by default)
if [[ -n "${IT2_ORIG_ZDOTDIR+X}" ]]; then
    'builtin' 'export' ZDOTDIR="$IT2_ORIG_ZDOTDIR"
    'builtin' 'unset' 'IT2_ORIG_ZDOTDIR'
else
    'builtin' 'unset' 'ZDOTDIR'
fi

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
    if [[ -o 'interactive' && -n "${ITERM_INJECT_SHELL_INTEGRATION-}" ]]; then
        # ${(%):-%x} is the path to the current file.
        # On top of it we add :A:h to get the directory.
        'builtin' 'typeset' _it2_file="${${(%):-%x}:A:h}"/iterm2_shell_integration.zsh
        if [[ -r "$_it2_file" ]]; then
            # The script below puts ~/.iterm2/bin first on PATH, but this file runs before the
            # rest of a login shell's startup files: /etc/zprofile's path_helper moves every
            # entry it doesn't know to the end, ~/.zprofile commonly prepends /opt/homebrew/bin,
            # and re-sourcing the script skips the prepend because the directory is already on
            # PATH. Any it2 earlier on PATH would then run instead of iTerm2's. So move it back
            # to the front once, before the first prompt, after every startup file has run.
            # PATH stays exported, so `sh -c` children get the same order. Registered before
            # the script runs so an error in the script can't skip it.
            _iterm2_put_bin_first() {
                # Ignore the options the startup files set: under ksh_arrays, for one,
                # $precmd_functions is only its first element.
                'builtin' 'emulate' '-L' 'zsh'
                precmd_functions=(${precmd_functions:#_iterm2_put_bin_first})
                'builtin' 'unfunction' '_iterm2_put_bin_first'
                'builtin' 'local' _it2_bin="${HOME}/.iterm2/bin" _it2_dir
                [[ -d "$_it2_bin" ]] || 'builtin' 'return' 0
                'builtin' 'local' -a _it2_rest
                for _it2_dir in "${path[@]}"; do
                    [[ "$_it2_dir" == "$_it2_bin" ]] || _it2_rest+=("$_it2_dir")
                done
                path=("$_it2_bin" "${_it2_rest[@]}")
                'builtin' 'export' PATH
            }
            precmd_functions=(_iterm2_put_bin_first ${precmd_functions[@]-})

            'builtin' 'autoload' '-Uz' '--' "$_it2_file"
            "${_it2_file:t}"
            'builtin' 'unfunction' '--' "${_it2_file:t}"
        fi
    fi
    'builtin' 'unset' '_it2_file'
}
