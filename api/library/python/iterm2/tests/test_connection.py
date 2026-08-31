"""Tests for iterm2.connection module."""
from types import SimpleNamespace
from unittest.mock import AsyncMock, MagicMock, patch

import pytest
import websockets.exceptions

from iterm2.connection import Connection


class TestIterm2ProtocolVersion:
    """Tests for the iterm2_protocol_version property."""

    def _make_connection_with_headers(self, headers):
        """Create a Connection with a mocked websocket having the given response headers."""
        conn = Connection()
        conn.websocket = SimpleNamespace(
            response=SimpleNamespace(headers=headers)
        )
        return conn

    def test_returns_version_tuple(self):
        """Test that a valid version header returns the correct tuple."""
        conn = self._make_connection_with_headers(
            {"X-iTerm2-Protocol-Version": "1.5"}
        )
        assert conn.iterm2_protocol_version == (1, 5)

    def test_returns_zero_when_header_missing(self):
        """Test that missing header returns (0, 0)."""
        conn = self._make_connection_with_headers({})
        assert conn.iterm2_protocol_version == (0, 0)

    def test_returns_zero_when_header_malformed(self):
        """Test that a malformed version header returns (0, 0)."""
        conn = self._make_connection_with_headers(
            {"X-iTerm2-Protocol-Version": "invalid"}
        )
        assert conn.iterm2_protocol_version == (0, 0)

    def test_returns_zero_when_header_has_too_many_parts(self):
        """Test that a version header with too many parts returns (0, 0)."""
        conn = self._make_connection_with_headers(
            {"X-iTerm2-Protocol-Version": "1.2.3"}
        )
        assert conn.iterm2_protocol_version == (0, 0)


class TestInvalidStatusHandling:
    """Tests for InvalidStatus exception handling in async_connect."""

    def _make_invalid_status(self, status_code):
        """Create an InvalidStatus exception with the given status code."""
        response = SimpleNamespace(status_code=status_code)
        return websockets.exceptions.InvalidStatus(response)

    @pytest.mark.asyncio
    async def test_async_connect_exits_on_406(self):
        """Test that async_connect calls sys.exit(1) on 406 status."""
        conn = Connection()
        exc = self._make_invalid_status(406)

        mock_context = AsyncMock()
        mock_context.__aenter__ = AsyncMock(side_effect=exc)
        mock_context.__aexit__ = AsyncMock(return_value=False)

        with patch.object(conn, 'authenticate', return_value=True), \
             patch.object(conn, '_remove_auth'), \
             patch.object(conn, '_get_connect_coro', return_value=mock_context), \
             pytest.raises(SystemExit) as exc_info:
            await conn.async_connect(AsyncMock(), retry=False)
        assert exc_info.value.code == 1

    @pytest.mark.asyncio
    async def test_async_connect_raises_on_other_status(self):
        """Test that async_connect re-raises on unexpected status codes."""
        conn = Connection()
        exc = self._make_invalid_status(500)

        mock_context = AsyncMock()
        mock_context.__aenter__ = AsyncMock(side_effect=exc)
        mock_context.__aexit__ = AsyncMock(return_value=False)

        with patch.object(conn, 'authenticate', return_value=True), \
             patch.object(conn, '_remove_auth'), \
             patch.object(conn, '_get_connect_coro', return_value=mock_context), \
             pytest.raises(websockets.exceptions.InvalidStatus) as exc_info:
            await conn.async_connect(AsyncMock(), retry=False)
        assert exc_info.value.response.status_code == 500

    @pytest.mark.asyncio
    async def test_async_connect_retries_on_401_without_fresh_cookie(self):
        """Test that async_connect re-authenticates on 401 when cookie is not fresh."""
        conn = Connection()
        exc_401 = self._make_invalid_status(401)

        mock_websocket = AsyncMock()

        mock_context_1 = AsyncMock()
        mock_context_1.__aenter__ = AsyncMock(side_effect=exc_401)
        mock_context_1.__aexit__ = AsyncMock(return_value=False)

        mock_context_2 = AsyncMock()
        mock_context_2.__aenter__ = AsyncMock(return_value=mock_websocket)
        mock_context_2.__aexit__ = AsyncMock(return_value=False)

        coro_results = [mock_context_1, mock_context_2]

        # authenticate is called 3 times:
        # 1. Top of loop, 1st iteration → False (not fresh)
        # 2. Inside 401 handler → True (re-authenticated)
        # 3. Top of loop, 2nd iteration → True
        auth_results = [False, True, True]

        mock_coro = AsyncMock(return_value="ok")
        mock_authenticate = MagicMock(side_effect=auth_results)

        with patch.object(conn, 'authenticate', mock_authenticate), \
             patch.object(conn, '_remove_auth'), \
             patch.object(conn, '_get_connect_coro', side_effect=coro_results):
            await conn.async_connect(mock_coro, retry=False)

        mock_authenticate.assert_any_call(True)
        mock_coro.assert_awaited_once()

    @pytest.mark.asyncio
    async def test_async_connect_raises_401_when_fresh_cookie(self):
        """Test that async_connect raises on 401 when cookie was already fresh."""
        conn = Connection()
        exc_401 = self._make_invalid_status(401)

        mock_context = AsyncMock()
        mock_context.__aenter__ = AsyncMock(side_effect=exc_401)
        mock_context.__aexit__ = AsyncMock(return_value=False)

        with patch.object(conn, 'authenticate', return_value=True), \
             patch.object(conn, '_remove_auth'), \
             patch.object(conn, '_get_connect_coro', return_value=mock_context), \
             pytest.raises(websockets.exceptions.InvalidStatus) as exc_info:
            await conn.async_connect(AsyncMock(), retry=False)
        assert exc_info.value.response.status_code == 401


class TestAsyncCreate:
    """Tests for the async_create static method."""

    def _make_invalid_status(self, status_code):
        """Create an InvalidStatus exception with the given status code."""
        response = SimpleNamespace(status_code=status_code)
        return websockets.exceptions.InvalidStatus(response)

    @pytest.mark.asyncio
    async def test_async_create_exits_on_406(self):
        """Test that async_create calls sys.exit(1) on 406 status."""
        exc = self._make_invalid_status(406)

        async def raise_exc():
            raise exc

        with patch.object(Connection, 'authenticate', return_value=True), \
             patch.object(Connection, '_remove_auth'), \
             patch.object(Connection, '_get_connect_coro', return_value=raise_exc()), \
             pytest.raises(SystemExit) as exc_info:
            await Connection.async_create()
        assert exc_info.value.code == 1

    @pytest.mark.asyncio
    async def test_async_create_raises_on_other_status(self):
        """Test that async_create re-raises on unexpected status codes."""
        exc = self._make_invalid_status(500)

        async def raise_exc():
            raise exc

        with patch.object(Connection, 'authenticate', return_value=True), \
             patch.object(Connection, '_remove_auth'), \
             patch.object(Connection, '_get_connect_coro', return_value=raise_exc()), \
             pytest.raises(websockets.exceptions.InvalidStatus) as exc_info:
            await Connection.async_create()
        assert exc_info.value.response.status_code == 500


class TestConnectCoroutineArgs:
    """Tests that connect methods pass correct arguments."""

    @patch('iterm2.connection._headers', return_value={"x-test": "value"})
    @patch('iterm2.connection._subprotocols', return_value=['api.iterm2.com'])
    @patch('iterm2.connection._uri', return_value='ws://localhost:1912')
    @patch('websockets.connect')
    def test_tcp_connect_uses_additional_headers(
            self, mock_connect, mock_uri, mock_subprotocols, mock_headers):
        """Test that _get_tcp_connect_coro uses additional_headers parameter."""
        conn = Connection()
        conn._get_tcp_connect_coro()
        mock_connect.assert_called_once_with(
            'ws://localhost:1912',
            ping_interval=None,
            close_timeout=0,
            additional_headers={"x-test": "value"},
            subprotocols=['api.iterm2.com'],
        )

    @patch('iterm2.connection._headers', return_value={"x-test": "value"})
    @patch('iterm2.connection._subprotocols', return_value=['api.iterm2.com'])
    @patch('websockets.unix_connect')
    def test_unix_connect_uses_additional_headers(
            self, mock_unix_connect, mock_subprotocols, mock_headers):
        """Test that _get_unix_connect_coro uses additional_headers parameter."""
        conn = Connection()
        with patch.object(conn, '_unix_domain_socket_path', return_value='/tmp/test.sock'):
            conn._get_unix_connect_coro()
        mock_unix_connect.assert_called_once_with(
            '/tmp/test.sock',
            'ws://localhost/',
            ping_interval=None,
            close_timeout=0,
            additional_headers={"x-test": "value"},
            subprotocols=['api.iterm2.com'],
            max_size=None,
        )
