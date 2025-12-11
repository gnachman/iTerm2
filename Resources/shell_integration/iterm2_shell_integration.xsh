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


class _iTerm2Xonsh:
    """iTerm2 integration with Xonsh shell."""

    def __init__(self):
        $ITERM2_INTEGRATION_PROMPT_BACKUP = @.env.get("PROMPT", "")

        if @.env.get('ITERM2_INTEGRATION_PROMPT', True):
            self.add_iterm_to_prompt()

        if @.env.get('ITERM2_INTEGRATION_EVENTS', True):
            self.add_iterm2_to_events()

        self.set_state()
        self.set_version()

        $ITERM2_INTEGRATION = True


    def set_state(self):
        if (user := @.env.get('USER', '')) and (host := @.env.get('HOSTNAME', '')):
            self.set_var("RemoteHost", f"{user}@{host}")

        if (cwd := @.env.get("PWD", @.imp.os.getcwd())):
            self.set_var("CurrentDir", cwd)


    def set_var(self, name, value):
        self.write_osc("1337;{name}={value}")


    def set_vars(self, vars):
        vars_str = ';'.join([f"{k}={v}" for k,v in vars.items()])
        self.write_osc("1337;{vars_str}")


    def set_user_var(self, key, value):
        b64value = @.imp.base64.b64encode(value.encode("utf-8")).decode("ascii").replace("\n", "")
        self.set_var("SetUserVar", f"{key}={b64value}")


    def _write_begin_osc(self):
        @.imp.sys.stdout.write("\033]")


    def _write_end_osc(self):
        @.imp.sys.stdout.write("\007")
        @.imp.sys.stdout.flush()


    def write_cr(self):
        if @.env.get("TERM_PROGRAM",'') == "iTerm.app":
            @.imp.sys.stdout.write("\r")
            @.imp.sys.stdout.flush()

    def write_osc(self, msg, cr=False):
        self._write_begin_osc()
        @.imp.sys.stdout.write(f"{msg}")
        if cr:
            self.write_cr()
        self._write_end_osc()


    def set_version(self):
        self.set_vars({"ShellIntegrationVersion":"18", "shell": "xonsh"})


    def write_prompt_start_osc(self):
        self.write_osc("133;A")
        return ""


    def write_prompt_end_osc(self):
        self.write_osc("133;B")
        return ""


    def _event_pre_prompt(self, **kwargs):
        self.set_state()


    def add_iterm2_to_events(self):
        # TODO: @events.on_precommand  # https://xon.sh/events.html

        @events.on_pre_prompt
        def _iterm2_on_preprompt(**kwargs):
            self._event_pre_prompt(**kwargs)

        # TODO: @events.on_post_prompt  # https://xon.sh/events.html


    def add_iterm_to_prompt(self):
        if 'iterm2_prompt_start' not in $PROMPT:
            $PROMPT_FIELDS['iterm2_prompt_start'] = self.write_prompt_start_osc
            $PROMPT_FIELDS['iterm2_prompt_end'] = self.write_prompt_end_osc
            $PROMPT = '{iterm2_prompt_start}' + $PROMPT + '{iterm2_prompt_end}'


if @.env.get('XONSH_INTERACTIVE', False) and @.env.get('TERM','') not in ['linux', 'dumb']:
    @.iterm2 = _iTerm2Xonsh()
