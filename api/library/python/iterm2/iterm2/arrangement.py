"""Provides access to saved arrangements."""

from __future__ import annotations

from collections.abc import Collection
from typing import TYPE_CHECKING

from .api_pb2 import CreateTabResponse, SavedArrangementResponse
from .capabilities import check_supports_list_saved_arrangements
from .rpc import (
    async_list_arrangements,
    async_restore_arrangement,
    async_save_arrangement,
)

if TYPE_CHECKING:
    from .connection import Connection


class SavedArrangementException(Exception):
    """A problem was encountered while saving or restoring an arrangement."""


class Arrangement:
    """Provides access to saved arrangements."""

    @staticmethod
    async def async_save(connection: Connection, name: str) -> None:
        """Save all windows as a new arrangement.

        Replaces the arrangement with the given name if it already exists.

        :param connection: The name of the arrangement.
        :param name: The name of the arrangement.

        :throws: SavedArrangementException
        """
        result = await async_save_arrangement(connection, name)
        status = result.saved_arrangement_response.status
        # pylint: disable=no-member
        if status != CreateTabResponse.Status.Value("OK"):
            raise SavedArrangementException(
                SavedArrangementResponse.Status.Name(
                    result.saved_arrangement_response.status
                )
            )

    @staticmethod
    async def async_restore(
        connection: Connection, name: str, window_id: str | None = None
    ) -> None:
        """Restore a saved window arrangement.

        :param connection: The name of the arrangement.
        :param name: The name of the arrangement to restore.
        :param window_id: The window to restore in to as tabs, or None to
             restore as new windows.

        :throws: SavedArrangementException
        """
        result = await async_restore_arrangement(connection, name, window_id)
        status = result.saved_arrangement_response.status
        # pylint: disable=no-member
        if status != CreateTabResponse.Status.Value("OK"):
            raise SavedArrangementException(
                SavedArrangementResponse.Status.Name(
                    result.saved_arrangement_response.status
                )
            )

    @staticmethod
    async def async_list(connection: Connection) -> Collection[str]:
        """Fetch a list of saved arrangements.

        NOTE: This requires iTerm2 version 3.4.0 or later.

        :param connection: The name of the arrangement.

        :returns: A list of strings giving saved arrangement names.

        :throws: SavedArrangementException
        """
        # Throw if iTerm2 is too old to support this feature.
        check_supports_list_saved_arrangements(connection)

        # Send the request
        result = await async_list_arrangements(connection)
        status = result.saved_arrangement_response.status

        # pylint: disable=no-member
        if status != CreateTabResponse.Status.Value("OK"):
            raise SavedArrangementException(
                SavedArrangementResponse.Status.Name(
                    result.saved_arrangement_response.status
                )
            )
        return result.saved_arrangement_response.names
