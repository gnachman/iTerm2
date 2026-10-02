from .connection import Connection

async def async_register_web_view_tool(
    connection: Connection,
    display_name: str,
    identifier: str,
    reveal_if_already_registered: bool,
    url: str,
) -> None: ...
