#!/usr/bin/env python3
"""Manual check for Session.async_eval_javascript (iterm2.browser_eval_js).

Serves a small page with a form from 127.0.0.1, opens it in a new browser
window, and runs a series of checks against it: reading the page, returning
values, awaiting, filling in a field, and getting exception messages back.
Nothing leaves the machine.

Run it against a dev build (see `make run`) with the Python API enabled:

    python3 tests/browser_eval_smoke.py

iTerm2 asks once whether to allow JavaScript on http://127.0.0.1:<port>. Click
OK. The port is different every run, so it asks every time. Each check prints
PASS or FAIL, and the exit status is nonzero if any failed.
"""
import asyncio
import http.server
import sys
import threading

import iterm2

PAGE = b"""<!doctype html>
<html>
<head><title>Eval Smoke Test</title></head>
<body>
<form>
  <input id="name" name="name">
</form>
<script>
  window.typed = [];
  document.getElementById("name").addEventListener("input", e => window.typed.push(e.target.value));
</script>
</body>
</html>
"""


class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(PAGE)))
        self.end_headers()
        self.wfile.write(PAGE)

    def log_message(self, format, *args):
        pass


def start_server():
    server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    return server


async def wait_for_page(session, title, timeout=30):
    """Waits until the test page has loaded. Until then the session may still
    be showing an earlier page, or no page at all, which fails the call."""
    deadline = asyncio.get_running_loop().time() + timeout
    while asyncio.get_running_loop().time() < deadline:
        try:
            if await session.async_eval_javascript(
                    "return document.readyState === 'complete' ? document.title : null") == title:
                return
        except iterm2.rpc.RPCException:
            pass
        await asyncio.sleep(0.25)
    raise TimeoutError("The test page did not load")


failures = []


def check(name, condition, detail=""):
    print(("PASS" if condition else "FAIL") + ": " + name + (f" ({detail})" if detail else ""))
    if not condition:
        failures.append(name)


async def expect_error(session, js, expected_substring):
    try:
        result = await session.async_eval_javascript(js)
    except iterm2.rpc.RPCException as e:
        return expected_substring in str(e), str(e)
    return False, f"no error; returned {result!r}"


async def main(connection):
    server = start_server()
    url = f"http://127.0.0.1:{server.server_address[1]}/"
    profile = iterm2.LocalWriteOnlyProfile()
    profile._simple_set("Custom Command", "Browser")
    profile._simple_set("Initial URL", url)
    window = await iterm2.Window.async_create(connection, profile_customizations=profile)
    session = window.current_tab.current_session
    try:
        await wait_for_page(session, "Eval Smoke Test")

        result = await session.async_eval_javascript(
            "return {title: document.title, n: 1 + 2, list: [true, null]}")
        check("returns structured values",
              result == {"title": "Eval Smoke Test", "n": 3, "list": [True, None]},
              repr(result))

        result = await session.async_eval_javascript("const x = 1;")
        check("no return gives None", result is None, repr(result))

        result = await session.async_eval_javascript(
            "return await new Promise(resolve => setTimeout(() => resolve('later'), 10))")
        check("await works", result == "later", repr(result))

        result = await session.async_eval_javascript(
            "const e = document.getElementById('name');"
            "e.value = 'Ada';"
            "e.dispatchEvent(new Event('input', {bubbles: true}));"
            "return window.typed")
        check("fills in a field the page sees", result == ["Ada"], repr(result))

        ok, detail = await expect_error(session, "throw new Error('kaboom')", "kaboom")
        check("thrown exception's message comes back", ok, detail)

        ok, detail = await expect_error(session, "return undefinedVariable", "undefinedVariable")
        check("reference error's message comes back", ok, detail)

        ok, detail = await expect_error(session, "return (", "JavaScript exception")
        check("syntax error is reported as an exception", ok, detail)
    finally:
        await window.async_close(force=True)
        server.shutdown()


iterm2.run_until_complete(main)
sys.exit(1 if failures else 0)
