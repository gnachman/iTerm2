"""Provides access to saved arrangements."""

import iterm2.rpc
import iterm2.api_pb2

class SavedArrangementException(Exception):
    """A problem was encountered while saving or restoring an arrangement."""
    pass

class Arrangement:
    @staticmethod
    async def async_save(connection, name):
        """Save all windows as a new arrangement.

        Replaces the arrangement with the given name if it already exists.

        :param name: The name of the arrangement.

        :throws: SavedArrangementException
        """
        result = await iterm2.rpc.async_save_arrangement(connection, name)
        status = result.saved_arrangement_response.status
        if status != iterm2.api_pb2.CreateTabResponse.Status.Value("OK"):
            raise SavedArrangementException(
                iterm2.api_pb2.SavedArrangementResponse.Status.Name(
                    result.saved_arrangement_response.status))

    @staticmethod
    async def async_restore(connection, name):
        """Restore a saved window arrangement.

        :param name: The name of the arrangement to restore.

        :throws: SavedArrangementException
        """
        result = await iterm2.rpc.async_restore_arrangement(connection, name)
        status = result.saved_arrangement_response.status
        if status != iterm2.api_pb2.CreateTabResponse.Status.Value("OK"):
            raise SavedArrangementException(
                iterm2.api_pb2.SavedArrangementResponse.Status.Name(
                    result.saved_arrangement_response.status))

