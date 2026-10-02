#!/usr/bin/env python3
"""Manual smoke test for iterm2.browser_eval_js (SC-6056).

Run against a dev build launched with `-suite claude-iterm2`:
    IT2_SUITE=claude-iterm2 IT2_APP_PATH=/path/to/iTerm2.app \
    PYTHONPATH=api/library/python/iterm2 python3 tests/browser_eval_smoke.py <url> [--login-github]

Opens a browser window on <url>, waits for it to load, reads document.title and the
signed-in GitHub user through Session.async_eval_javascript, and (with --login-github)
signs in by filling the form in the DOM — no clicks on the screen.

--login-github reads GITHUB_USER and GITHUB_PASSWORD, and GITHUB_TOTP_CMD (a command
that prints the current two-factor code) if the account has 2FA.
"""
import asyncio
import json
import os
import subprocess
import sys

import iterm2

URL = sys.argv[1] if len(sys.argv) > 1 else "https://example.com/"
LOGIN = "--login-github" in sys.argv


def totp():
    return subprocess.run(os.environ["GITHUB_TOTP_CMD"], shell=True,
                          capture_output=True, text=True, check=True).stdout.strip()


async def wait_ready(session, timeout=30):
    for _ in range(timeout * 2):
        try:
            state = await session.async_eval_javascript("return document.readyState")
            if state == "complete":
                return True
        except Exception as e:  # page not committed yet
            last = e
        await asyncio.sleep(0.5)
    return False


async def wait_url(session, pred, timeout=20):
    for _ in range(timeout * 2):
        try:
            url = await session.async_eval_javascript("return location.href")
            if pred(url):
                return url
        except Exception:
            pass  # mid-navigation
        await asyncio.sleep(0.5)
    return None


async def page(session):
    return await session.async_eval_javascript(
        "return {title: document.title, url: location.href, "
        "user: document.querySelector('meta[name=user-login]')?.content || null}")


async def set_field(session, selector, value):
    # Native setter + input event, so the page sees a typed value.
    js = ("const e = document.querySelector(" + json.dumps(selector) + ");"
          "if (!e) return false;"
          "Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value').set.call(e, " + json.dumps(value) + ");"
          "e.dispatchEvent(new Event('input', {bubbles: true}));"
          "return true;")
    return await session.async_eval_javascript(js)


async def main(connection):
    profile = iterm2.LocalWriteOnlyProfile()
    profile._simple_set("Custom Command", "Browser")
    profile._simple_set("Initial URL", URL)
    window = await iterm2.Window.async_create(connection, profile_customizations=profile)
    session = window.current_tab.current_session
    await asyncio.sleep(2)
    print("ready:", await wait_ready(session))
    if "--logout-first" in sys.argv and (await page(session))["user"]:
        # GitHub's sign-out is a POST form on /logout; submit it from the DOM.
        await session.async_load_url("https://github.com/logout")
        await wait_url(session, lambda u: "/logout" in u)
        await wait_ready(session)
        await session.async_eval_javascript(
            "const f = document.querySelector('form[action=\"/logout\"]'); setTimeout(() => f.requestSubmit(), 50); return true")
        print("logged out ->", await wait_url(session, lambda u: "/logout" not in u))
        await session.async_load_url(URL)
        await wait_url(session, lambda u: u.startswith(URL) or "/login" in u)
        await wait_ready(session)
    print("before:", json.dumps(await page(session)))
    if LOGIN and (await page(session))["user"] is None:
        await session.async_load_url("https://github.com/login?return_to=" + URL)
        await wait_url(session, lambda u: "/login" in u)
        await wait_ready(session)
        await set_field(session, "#login_field", os.environ["GITHUB_USER"])
        await set_field(session, "#password", os.environ["GITHUB_PASSWORD"])
        await asyncio.sleep(1)
        await session.async_eval_javascript("const f = document.querySelector('#login_field').form; setTimeout(() => f.requestSubmit(f.querySelector('input[name=commit]')), 50); return true")
        if not await wait_url(session, lambda u: "/session" in u or "two-factor" in u or u.startswith(URL), timeout=30):
            print("login stuck:", json.dumps(await session.async_eval_javascript(
                "return {url: location.href, filled: (document.querySelector('#login_field')||{}).value?.length, flash: [...document.querySelectorAll('.flash-error, .js-flash-alert, [role=alert]')].map(e => e.innerText.trim()).join(' | ').slice(0, 300)}")))
        await wait_ready(session)
        has_totp = False
        for attempt in range(40):
            if attempt == 10 and "two-factor" in (await session.async_eval_javascript("return location.href")):
                # GitHub may default to a passkey / GitHub Mobile method; the TOTP form is here.
                await session.async_load_url("https://github.com/sessions/two-factor/app")
                await wait_url(session, lambda u: u.endswith("/two-factor/app"))
                await wait_ready(session)
            try:
                has_totp = await session.async_eval_javascript("return !!document.querySelector('#app_totp')")
            except Exception:
                pass
            if has_totp:
                break
            await asyncio.sleep(0.5)
        if not has_totp:
            print("2fa page:", json.dumps(await session.async_eval_javascript(
                "return {url: location.href, inputs: [...document.querySelectorAll('input')].filter(e => e.type !== 'hidden').map(e => e.type + '#' + e.id + '/' + e.name), links: [...document.querySelectorAll('a,button')].map(e => (e.innerText||'').trim()).filter(t => t && t.length < 60).slice(0, 25)}")))
        if has_totp:
            await set_field(session, "#app_totp", totp())
            # GitHub's TOTP box submits itself on input; a second explicit submit re-sends the
            # same code ("already been used"). Only submit if the page has not moved on.
            moved = await wait_url(session, lambda u: "two-factor" not in u, timeout=6)
            if not moved:
                await session.async_eval_javascript(
                    "const f = document.querySelector('#app_totp')?.form; if (f) setTimeout(() => f.requestSubmit(), 50); return true")
                moved = await wait_url(session, lambda u: "two-factor" not in u)
            await wait_ready(session)
            if not moved:
                print("2fa stuck:", json.dumps(await session.async_eval_javascript(
                    "return {url: location.href, value: (document.querySelector('#app_totp')||{}).value?.length, flash: [...document.querySelectorAll('.flash, .flash-error, [role=alert]')].map(e => e.innerText.trim()).join(' | ')}")))
        if not (await page(session))["url"].startswith(URL):
            await session.async_load_url(URL)
            await wait_ready(session)
        print("after:", json.dumps(await page(session)))
    await session.async_set_browser_inspectable(True)
    print("inspectable: ok")


# Get the API cookie from the test instance via osascript (IT2_APP_PATH picks the app).
import iterm2.auth
_ck = iterm2.auth.request_cookie_and_key(False, "browser_eval_smoke", iterm2.auth.CommandLineApplescriptRunner).split(" ")
os.environ["ITERM2_COOKIE"], os.environ["ITERM2_KEY"] = _ck[0], _ck[1]
iterm2.run_until_complete(main)
