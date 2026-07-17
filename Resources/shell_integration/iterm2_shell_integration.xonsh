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

# ShellIntegrationVersion=2;shell=xonsh

class _iTerm2Xonsh:
    """iTerm2 integration with Xonsh shell."""

    def __init__(self):
        self.version = 2
        self.stdout = @.imp.sys.__stdout__

        # OSC 133 aid: per-command identifier the receiver uses to target a
        # specific mark for D-by-aid (and cascade-close when an outer
        # command like ssh dies before its inner remote shell's D
        # arrives).
        self.aid_salt = @.imp.os.urandom(4).hex()
        self.aid_counter = 0
        self.current_aid = f"{self.aid_salt}-0"

        self.add_iterm2_to_env()
        if self.is_iterm2_interactive():
            self.add_iterm2_to_prompt_fields()
            self.add_iterm2_to_prompt()  # Wrap prompt immediately for first prompt
            self.add_iterm2_to_events()
            self.set_state()
            self.set_version()
            $ITERM2_INTEGRATION = True
        else:
            $ITERM2_INTEGRATION = False


    def add_iterm2_to_env(self):
        @.env.register('ITERM2_INTEGRATION', type='bool', default=False,
                       doc="Has `True` if iTerm2 integration was enabled or `False` overwise.")
        @.env.register('ITERM2_INTEGRATION_DEBUG', type='bool', default=False,
                       doc="Set to `True` to enable debug messages.")
        @.env.register('ITERM_ENABLE_SHELL_INTEGRATION_WITH_TMUX', type='bool', default=False,
                       doc="By default, shell Integration does not work with tmux or screen. "
                           "If you'd like to use it with tmux, set `True`. "
                           "Docs: https://iterm2.com/documentation-shell-integration.html")

    def print_err(self, msg):
        print(msg, file=@.imp.sys.stderr)

    def is_iterm2_interactive(self):
        if not @.env.get('XONSH_INTERACTIVE', False):
            if $ITERM2_INTEGRATION_DEBUG:
                self.print_err('iTerm2 Integration: xonsh is not interactive.')
            return False

        term = @.env.get('TERM', '')
        if term in ('linux', 'dumb'):
            if $ITERM2_INTEGRATION_DEBUG:
                self.print_err('iTerm2 Integration: $TERM is not supported.')
            return False

        tmux_enabled = @.env.get('ITERM_ENABLE_SHELL_INTEGRATION_WITH_TMUX')
        if not tmux_enabled and term in ('screen', 'screen-256color', 'tmux-256color'):
            if $ITERM2_INTEGRATION_DEBUG:
                self.print_err('iTerm2 Integration: tmux is not enabled.')
            return False

        if 'iTerm' not in (term_program := @.env.get('TERM_PROGRAM', '')):
            if $ITERM2_INTEGRATION_DEBUG:
                self.print_err(f'iTerm2 Integration: iTerm not in $TERM_PROGRAM {term_program}.')
            return False

        return True


    def _get_hostname(self):
        if (iterm2_hostname := @.env.get('iterm2_hostname', '')):
            return iterm2_hostname

        try:
            if (host := $(hostname -f 2> /dev/null)):
                return host
        except Exception:
            pass

        try:
            if (host := $(hostname 2> /dev/null)):
                return host
        except Exception:
            pass

        return @.env.get('HOSTNAME', '')

    def set_state(self):
        if (user := @.env.get('USER', '')) and (host := self._get_hostname()):
            self.set_var("RemoteHost", f"{user}@{host}")

        if (cwd := @.env.get("PWD", @.imp.os.getcwd())):
            self.set_var("CurrentDir", cwd)

    def set_var(self, name, value):
        self.write_osc(f"1337;{name}={value}")

    def set_vars(self, vars):
        vars_str = ';'.join([f"{k}={v}" for k,v in vars.items()])
        self.write_osc(f"1337;{vars_str}")

    def set_user_var(self, key, value):
        b64value = @.imp.base64.b64encode(value.encode("utf-8")).decode("ascii").replace("\n", "")
        self.set_var("SetUserVar", f"{key}={b64value}")

    def _write_begin_osc(self):
        self.stdout.write("\033]")

    def _write_end_osc(self):
        self.stdout.write("\007")
        self.stdout.flush()

    def write_cr(self):
        if @.env.get("TERM_PROGRAM",'') == "iTerm.app":
            self.stdout.write("\r")
            self.stdout.flush()

    def write_osc(self, msg, cr=False):
        self._write_begin_osc()
        self.stdout.write(f"{msg}")
        if cr:
            self.write_cr()
        self._write_end_osc()

    def set_version(self):
        self.set_vars({"ShellIntegrationVersion": str(self.version), "shell": "xonsh"})

    def write_preexec_osc(self):
        self.write_osc(f"133;C;aid={self.current_aid}", cr=True)

    def write_return_code_osc(self, return_code):
        # Uses the OLD aid (the one in effect for the just-finished command);
        # _event_pre_prompt rolls AFTER this fires so the next A/B/C uses
        # the new aid.
        self.write_osc(f"133;D;{return_code};aid={self.current_aid}")

    # Integrations

    def add_iterm2_to_prompt_fields(self):
        """
        Official prompt-toolkit example:
        https://github.com/prompt-toolkit/python-prompt-toolkit/blob/c7c629c38b22b5f22a0a5e80a1ae7e758ac595bb/examples/prompts/finalterm-shell-integration.py
        """
        # Callable fields are evaluated each prompt render, so A/B pick up
        # the current aid that _event_pre_prompt just rolled.
        $PROMPT_FIELDS['iterm2_prompt_start'] = lambda: (
            "\001" + f"\033]133;A;aid={self.current_aid}\a" + "\002"
        )
        $PROMPT_FIELDS['iterm2_prompt_end'] = lambda: (
            "\001" + f"\033]133;B;aid={self.current_aid}\a" + "\002"
        )

    def add_iterm2_to_prompt(self):
        if isinstance($PROMPT, str) and 'iterm2_prompt_start' not in $PROMPT:
            $PROMPT = '{iterm2_prompt_start}' + $PROMPT + '{iterm2_prompt_end}'


    # Events

    def _is_supported_shell_type(self):
        """Check SHELL_TYPE at prompt time when it's reliably set."""
        shell_type = @.env.get('SHELL_TYPE', '')
        return shell_type in ('prompt_toolkit', 'best', 'random', 'readline')

    def _event_pre_prompt(self, **kwargs):
        if not self._is_supported_shell_type():
            if $ITERM2_INTEGRATION_DEBUG:
                shell_type = @.env.get('SHELL_TYPE', '')
                self.print_err(f'iTerm2 Integration: SHELL_TYPE {repr(shell_type)} not supported.')
            return
        # Roll the per-command aid AFTER post_command's D has fired (with
        # the old aid) and BEFORE the next prompt is rendered (A/B will
        # see the new value via the PROMPT_FIELDS lambdas). on_precommand
        # then emits C with the same new aid before the command runs.
        self.aid_counter += 1
        self.current_aid = f"{self.aid_salt}-{self.aid_counter}"
        self.add_iterm2_to_prompt()
        self.set_state()

    def _event_pre_command(self, **kwargs):
        if not self._is_supported_shell_type():
            return
        self.write_preexec_osc()

    def _event_post_command(self, **kwargs):
        if not self._is_supported_shell_type():
            return
        self.write_return_code_osc(kwargs.get('rtn', 0))

    def add_iterm2_to_events(self):

        @events.on_pre_prompt
        def _iterm2_on_preprompt(**kwargs):
            self._event_pre_prompt(**kwargs)

        @events.on_precommand
        def _iterm2_on_precommand(**kwargs):
            self._event_pre_command(**kwargs)

        @events.on_postcommand
        def _iterm2_on_postcommand(**kwargs):
            self._event_post_command(**kwargs)


__xonsh__.iterm2 = _iTerm2Xonsh()

# it2 CLI over iTerm2 SSH integration: materialize the embedded copy (named by
# content hash, so a shipped update replaces a stale one) and register an it2 alias
# unless it2 already exists. Check aliases too: shutil.which only searches PATH and
# would miss (and clobber) a user-defined it2 alias. Without python3 (or if the
# install fails) alias it2 to a clear message rather than a broken path.
try:
    import shutil as _iterm2_shutil, sys as _iterm2_sys
    if "it2" not in aliases and _iterm2_shutil.which("it2") is None:
        import os as _iterm2_os
        _iterm2_dir = _iterm2_os.path.expanduser("~/.iterm2")
        _iterm2_it2_path = _iterm2_os.path.join(_iterm2_dir, "it2.4a5c7f87cc6e339b.py")
        _iterm2_py = _iterm2_shutil.which("python3")
        if _iterm2_py and not _iterm2_os.path.exists(_iterm2_it2_path):
            import base64 as _iterm2_b64, glob as _iterm2_glob, gzip as _iterm2_gzip, tempfile as _iterm2_tf
            _iterm2_os.makedirs(_iterm2_dir, exist_ok=True)
            _iterm2_fd, _iterm2_tmp = _iterm2_tf.mkstemp(dir=_iterm2_dir)
            try:
                _iterm2_os.write(_iterm2_fd, _iterm2_gzip.decompress(_iterm2_b64.b64decode("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")))
                _iterm2_os.close(_iterm2_fd)
                _iterm2_os.replace(_iterm2_tmp, _iterm2_it2_path)
            except OSError:
                try:
                    _iterm2_os.close(_iterm2_fd)
                except OSError:
                    pass
                try:
                    _iterm2_os.remove(_iterm2_tmp)
                except OSError:
                    pass
            else:
                for _iterm2_old in _iterm2_glob.glob(_iterm2_os.path.join(_iterm2_dir, "it2*.py")):
                    if _iterm2_old != _iterm2_it2_path:
                        try:
                            _iterm2_os.remove(_iterm2_old)
                        except OSError:
                            pass
        if _iterm2_py and _iterm2_os.path.exists(_iterm2_it2_path):
            aliases["it2"] = [_iterm2_py, _iterm2_it2_path]
        else:
            def _iterm2_it2(args):
                _iterm2_sys.stderr.write("it2: python3 is required\n" if not _iterm2_py else "it2: could not be installed\n")
                return 1
            aliases["it2"] = _iterm2_it2
except Exception:
    pass
