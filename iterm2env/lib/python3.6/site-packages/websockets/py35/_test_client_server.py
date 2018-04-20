# Tests containing Python 3.5+ syntax, extracted from test_client_server.py.

import asyncio
import unittest

from ..client import *
from ..server import *
from ..test_client_server import get_server_uri, handler


class ContextManagerTests(unittest.TestCase):

    def setUp(self):
        self.loop = asyncio.new_event_loop()
        asyncio.set_event_loop(self.loop)

    def tearDown(self):
        self.loop.close()

    def test_client(self):
        start_server = serve(handler, 'localhost', 0)
        server = self.loop.run_until_complete(start_server)

        async def run_client():
            async with connect(get_server_uri(server)) as client:
                await client.send("Hello!")
                reply = await client.recv()
                self.assertEqual(reply, "Hello!")

        self.loop.run_until_complete(run_client())

        server.close()
        self.loop.run_until_complete(server.wait_closed())

    def test_server(self):
        async def run_server():
            async with serve(handler, 'localhost', 0) as server:
                client = await connect(get_server_uri(server))
                await client.send("Hello!")
                reply = await client.recv()
                self.assertEqual(reply, "Hello!")

        self.loop.run_until_complete(run_server())
