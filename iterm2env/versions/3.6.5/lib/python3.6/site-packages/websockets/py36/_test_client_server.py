# Tests containing Python 3.6+ syntax, extracted from test_client_server.py.

import asyncio
import sys
import unittest

from ..client import *
from ..exceptions import ConnectionClosed
from ..server import *
from ..test_client_server import get_server_uri


# Fail at import time, not just at run time, to prevent test
# discovery.
if sys.version_info[:2] < (3, 6):                           # pragma: no cover
    raise ImportError("Python 3.6+ only")


MESSAGES = ['3', '2', '1', 'Fire!']


class AsyncIteratorTests(unittest.TestCase):

    # This is a protocol-level feature, but since it's a high-level API, it is
    # much easier to exercise at the client or server level.

    def setUp(self):
        self.loop = asyncio.new_event_loop()
        asyncio.set_event_loop(self.loop)

    def tearDown(self):
        self.loop.close()

    def test_iterate_on_messages(self):

        async def handler(ws, path):
            for message in MESSAGES:
                await ws.send(message)

        start_server = serve(handler, 'localhost', 0)
        server = self.loop.run_until_complete(start_server)

        messages = []

        async def run_client():
            nonlocal messages
            async with connect(get_server_uri(server)) as ws:
                async for message in ws:
                    messages.append(message)

        self.loop.run_until_complete(run_client())

        self.assertEqual(messages, MESSAGES)

        server.close()
        self.loop.run_until_complete(server.wait_closed())

    def test_iterate_on_messages_exit_not_ok(self):

        async def handler(ws, path):
            for message in MESSAGES:
                await ws.send(message)
            await ws.close(1001)

        start_server = serve(handler, 'localhost', 0)
        server = self.loop.run_until_complete(start_server)

        messages = []

        async def run_client():
            nonlocal messages
            async with connect(get_server_uri(server)) as ws:
                async for message in ws:
                    messages.append(message)

        with self.assertRaises(ConnectionClosed):
            self.loop.run_until_complete(run_client())

        self.assertEqual(messages, MESSAGES)

        server.close()
        self.loop.run_until_complete(server.wait_closed())
