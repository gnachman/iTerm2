.. _unread_example:

Unread Count and Status Bar Icon
================================

This example demonstrates a custom status bar component that shows an "unread count" and has an icon.

Status bar icons should be a pair of PNGs: a low-DPI one of size 16x17 pixels, and a high-DPI one of size 32x34 pixels. It is recommended to leave a 2px/4px margin around the image. These PNGs are then base64-encoded and passed to the `StatusBarComponent` initializer as `StatusBarComponent.Icon` objects.

The unread count is a number in a red circle that tells the user that their attention is needed.

.. code-block:: python

    import iterm2
    import datetime

    dict={}
    async def main(connection):
        icon2x = iterm2.StatusBarComponent.Icon(2, "iVBORw0KGgoAAAANSUhEUgAAACAAAAAiCAYAAAA+stv/AAAABGdBTUEAALGPC/xhBQAAAAFzUkdCAK7OHOkAAAAgY0hSTQAAeiYAAICEAAD6AAAAgOgAAHUwAADqYAAAOpgAABdwnLpRPAAAAjpJREFUWMPt10tIVVEUBuBPSyFJJEuIghpFZVAQNLNBEGHQQ3pAQYXUQEQoaeKs5hE0i6BBUYRQhAX2MDGRQmrSoCgiek00soweSFSYTVZwON2r9+htEPnD5XDWXnvt/6z1r733ZRrT+N9RktF/FurRgGVYiFEM4iE60IMfxSY6A014i7FY8ApO4hQ68T7GXmNXMRefg94I3oW6PJmbiQ3oD9/LkbEpYR6eYgQ7M8xrjjLcQ8VU0t6DL1iTsDdiXw7/FmxPvNcHifbJEjgcqdyRsveiO4f/Y1xI2Q5GjMyaqMS7ULU8BGZjCC/HIQD38Sw08gdK8xDYHfU/MkEL14TfeDiKJVGSgglsxhM8KkIXdWM4YuZsnVxYizN5xvpi80njFl7lsI+GmOsKZVwRwmktQCdj+FxAzGP4WGgJ5sZzuIib2TCqorUnJPAhntUFlquQ0lbjU67S5SIwEmldlLCdw9UMG1h/pP03FuNNlpRdT3XAgaj3ngLmtoXvxsRHDuF0FgLNEaQ20fNd+D7BmdCCnzibsK2PWFuzEKgKLVxKdcfNCNYZAZdiRZDqi7HzKQ3cjd2yLKty2+JrtiRs5TiEgVgs+XuO/amjuinG9k6mdcpwJ9S7KjVWjpXYFpmozdFi6/At7gUlk+3f+XgRXbEpw7zGWPxBHFpTQk3iltOB1eMcTnW4Hb7XirF4shytIcyxEFU7juMELiZ0MRhaKP0bt+LKONUasBwLQqgDsW904Aa+Tv/hmMY/g19dRocbAnQakwAAAABJRU5ErkJggg==")
        icon1x = iterm2.StatusBarComponent.Icon(1, "iVBORw0KGgoAAAANSUhEUgAAABAAAAARCAYAAADUryzEAAAABGdBTUEAALGPC/xhBQAAAAFzUkdCAK7OHOkAAAAgY0hSTQAAeiYAAICEAAD6AAAAgOgAAHUwAADqYAAAOpgAABdwnLpRPAAAAPFJREFUOMvd0r8rxVEYx/FXIkphtPk1XSVRN5SUDAYZDJcyIJOM8iMTSTd1dReDQTcLpdiUBSn+McujThzf7iifOvU8n9PzPs9zzuHfahmXeMQTLrDUTGEbnnGNElrDGw5IDS1FgH0cRlxP/HoU1nDyW/E4ruJEeMUxdiOGdtxGdz+0gq0kb6AaHTUSfweLOcARZr551WSkL81jLwfYRgVzGMwARjCJdWzkAAs4QC8+0J/sDYXXF/cymwN04g2jMcoDznAe/2EAE7hBR9FLvES7PQEbQzfKeI+8UGXc4RSrWIv4PkZpSl2YxmasqRjxD+oTx8sma7lYSGAAAAAASUVORK5CYII=")

        component = iterm2.StatusBarComponent(
            short_description="Unread Count",
            detailed_description="Shows the time since you clicked the component.",
            knobs=[],
            exemplar="Unread Count Demo",
            update_cadence=1,
            identifier="com.iterm2.example.unread-count",
            icons=[icon1x,icon2x])

        # This function gets called once per second.
        @iterm2.StatusBarRPC
        async def coro(knobs, session_id=iterm2.Reference("id")):
            global dict
            if session_id in dict:
                j = dict[session_id] + 1
            else:
                j = 1
            await component.async_set_unread_count(session_id, j)
            dict[session_id] = j

            return "Demo"

        @iterm2.RPC
        async def reset(session_id):
            global dict
            dict[session_id] = 0
            await component.async_set_unread_count(session_id, 0)

        # Register the component.
        await component.async_register(connection, coro, onclick=reset)

    iterm2.run_forever(main)


:Download:`Download<unread.its>`
