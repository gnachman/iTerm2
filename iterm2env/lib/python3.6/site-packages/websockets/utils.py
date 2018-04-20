import itertools


__all__ = ['apply_mask']


def apply_mask(data, mask):
    """
    Apply masking to websocket message.

    """
    if len(mask) != 4:
        raise ValueError("mask must contain 4 bytes")
    return bytes(b ^ m for b, m in zip(data, itertools.cycle(mask)))
