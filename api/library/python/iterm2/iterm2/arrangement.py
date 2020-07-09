"""Provides access to saved arrangements."""

import iterm2.capabilities
import iterm2.connection
import iterm2.rpc
import iterm2.api_pb2
import typing


class SavedArrangementException(Exception):
    """A problem was encountered while saving or restoring an arrangement."""


class Arrangement:
    """Provides access to saved arrangements."""
    @staticmethod
    async def async_save(connection: iterm2.connection.Connection, name: str):
        """Save all windows as a new arrangement.

        Replaces the arrangement with the given name if it already exists.

        :param connection: The name of the arrangement.
        :param name: The name of the arrangement.

        :throws: SavedArrangementException
        """
        result = await iterm2.rpc.async_save_arrangement(connection, name)
        status = result.saved_arrangement_response.status
        # pylint: disable=no-member
        if status != iterm2.api_pb2.CreateTabResponse.Status.Value("OK"):
            raise SavedArrangementException(
                iterm2.api_pb2.SavedArrangementResponse.Status.Name(
                    result.saved_arrangement_response.status))

    @staticmethod
    async def async_restore(
            connection: iterm2.connection.Connection, name: str):
        """Restore a saved window arrangement.

        :param connection: The name of the arrangement.
        :param name: The name of the arrangement to restore.

        :throws: SavedArrangementException
        """
        result = await iterm2.rpc.async_restore_arrangement(connection, name)
        status = result.saved_arrangement_response.status
        # pylint: disable=no-member
        if status != iterm2.api_pb2.CreateTabResponse.Status.Value("OK"):
            raise SavedArrangementException(
                iterm2.api_pb2.SavedArrangementResponse.Status.Name(
                    result.saved_arrangement_response.status))
    @staticmethod
    async def async_list(
            connection: iterm2.connection.Connection) -> typing.List[str]:
        """Fetch a list of saved arrangements.

        NOTE: This requires iTerm2 version 3.4.0 or later.

        :param connection: The name of the arrangement.

        :returns: A list of strings giving saved arrangement names.

        :throws: SavedArrangementException
        """
        # Throw if iTerm2 is too old to support this feature.
        iterm2.capabilities.check_supports_list_saved_arrangements(connection)

        # Send the request
        result = await iterm2.rpc.async_list_arrangements(connection)
        status = result.saved_arrangement_response.status

        # pylint: disable=no-member
        if status != iterm2.api_pb2.CreateTabResponse.Status.Value("OK"):
            raise SavedArrangementException(
                iterm2.api_pb2.SavedArrangementResponse.Status.Name(
                    result.saved_arrangement_response.status))
        return result.saved_arrangement_response.names

