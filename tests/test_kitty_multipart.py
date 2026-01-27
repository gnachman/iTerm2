#!/usr/bin/env python3
"""
Test script for kitty image protocol multipart transmission.

Tests both single-part and multi-part image transmissions to verify
that iTerm2 correctly handles base64 chunks that are encoded independently
(which may have padding in non-final chunks).

Usage: python3 test_kitty_multipart.py
"""

import base64
import sys
import time

def kitty_cmd(params, payload=""):
    """Generate a kitty graphics protocol escape sequence."""
    return f"\x1b_G{params};{payload}\x1b\\"

def create_rgba_image(width, height, color):
    """Create a simple solid-color RGBA image."""
    r, g, b, a = color
    return bytes([r, g, b, a] * (width * height))

def test_single_part():
    """Test single-part transmission (baseline - should always work)."""
    print("Test 1: Single-part transmission (baseline)")
    print("-" * 50)

    # 2x2 red image
    data = create_rgba_image(2, 2, (255, 0, 0, 255))
    encoded = base64.b64encode(data).decode()

    print(f"  Image: 2x2 red RGBA ({len(data)} bytes)")
    print(f"  Base64: {encoded}")
    print(f"  Transmitting as single chunk...")

    # Transmit then display (same pattern as other tests)
    sys.stdout.write(kitty_cmd("a=t,f=32,s=2,v=2,i=100,m=0", encoded))
    sys.stdout.write(kitty_cmd("a=p,i=100,c=2,r=2", ""))
    sys.stdout.flush()

    print("  Expected: Red square above")
    print()

def test_multipart_stream_encoding():
    """Test multi-part with stream encoding (chunks from single base64 stream)."""
    print("Test 2: Multi-part with stream encoding")
    print("-" * 50)

    # 2x2 green image
    data = create_rgba_image(2, 2, (0, 255, 0, 255))
    encoded = base64.b64encode(data).decode()

    # Split the base64 string (not the raw data)
    mid = len(encoded) // 2
    chunk1 = encoded[:mid]
    chunk2 = encoded[mid:]

    print(f"  Image: 2x2 green RGBA ({len(data)} bytes)")
    print(f"  Full base64: {encoded}")
    print(f"  Chunk 1: {chunk1}")
    print(f"  Chunk 2: {chunk2}")
    print(f"  Transmitting as 2 chunks (stream split)...")

    # Transmit in parts
    sys.stdout.write(kitty_cmd("a=t,f=32,s=2,v=2,i=101,m=1", chunk1))
    sys.stdout.write(kitty_cmd("a=t,f=32,i=101,m=0", chunk2))
    # Display
    sys.stdout.write(kitty_cmd("a=p,i=101,c=2,r=2", ""))
    sys.stdout.flush()

    print("  Expected: Green square above")
    print("  (This should work on both old and new versions)")
    print()

def test_multipart_independent_encoding():
    """Test multi-part with independent chunk encoding (the bug case)."""
    print("Test 3: Multi-part with independent chunk encoding (BUG TEST)")
    print("-" * 50)

    # 2x2 blue image
    data = create_rgba_image(2, 2, (0, 0, 255, 255))

    # Split raw data and encode each chunk independently
    # This creates padding in the first chunk
    mid = len(data) // 2
    raw_chunk1 = data[:mid]
    raw_chunk2 = data[mid:]

    chunk1 = base64.b64encode(raw_chunk1).decode()
    chunk2 = base64.b64encode(raw_chunk2).decode()

    print(f"  Image: 2x2 blue RGBA ({len(data)} bytes)")
    print(f"  Raw chunk 1: {len(raw_chunk1)} bytes -> base64: {chunk1}")
    print(f"  Raw chunk 2: {len(raw_chunk2)} bytes -> base64: {chunk2}")
    print(f"  Note: First chunk has padding ('=' at end)")
    print(f"  Transmitting as 2 independently-encoded chunks...")

    # Transmit in parts
    sys.stdout.write(kitty_cmd("a=t,f=32,s=2,v=2,i=102,m=1", chunk1))
    sys.stdout.write(kitty_cmd("a=t,f=32,i=102,m=0", chunk2))
    # Display
    sys.stdout.write(kitty_cmd("a=p,i=102,c=2,r=2", ""))
    sys.stdout.flush()

    print("  Expected: Blue square above")
    print("  OLD VERSION: Will likely show nothing or error")
    print("  NEW VERSION: Should show blue square")
    print()

def test_multipart_many_chunks():
    """Test multi-part with many small independently-encoded chunks."""
    print("Test 4: Multi-part with many small chunks")
    print("-" * 50)

    # 4x4 yellow image
    data = create_rgba_image(4, 4, (255, 255, 0, 255))

    # Split into 4-byte chunks (1 pixel each) and encode independently
    chunk_size = 4
    chunks = []
    for i in range(0, len(data), chunk_size):
        raw_chunk = data[i:i+chunk_size]
        chunks.append(base64.b64encode(raw_chunk).decode())

    print(f"  Image: 4x4 yellow RGBA ({len(data)} bytes)")
    print(f"  Split into {len(chunks)} chunks of {chunk_size} bytes each")
    print(f"  Each chunk encoded independently (all have padding)")
    print(f"  Chunks: {chunks[:3]}... (showing first 3)")
    print(f"  Transmitting...")

    # Transmit first chunk
    sys.stdout.write(kitty_cmd("a=t,f=32,s=4,v=4,i=103,m=1", chunks[0]))
    # Transmit middle chunks
    for chunk in chunks[1:-1]:
        sys.stdout.write(kitty_cmd("a=t,f=32,i=103,m=1", chunk))
    # Transmit final chunk
    sys.stdout.write(kitty_cmd("a=t,f=32,i=103,m=0", chunks[-1]))
    # Display
    sys.stdout.write(kitty_cmd("a=p,i=103,c=4,r=4", ""))
    sys.stdout.flush()

    print("  Expected: Yellow square above")
    print("  OLD VERSION: Will likely show nothing or error")
    print("  NEW VERSION: Should show yellow square")
    print()

def test_minimal_repro():
    """Minimal reproduction case from the bug report."""
    print("Test 5: Minimal reproduction (1x1 pixel, 2 chunks)")
    print("-" * 50)

    # 1x1 RGBA magenta pixel (4 bytes)
    data = bytes([255, 0, 255, 255])

    # Encode each 2-byte chunk independently
    chunk1 = base64.b64encode(data[:2]).decode()  # /wA=
    chunk2 = base64.b64encode(data[2:]).decode()  # /wD/

    print(f"  Image: 1x1 magenta RGBA ({len(data)} bytes)")
    print(f"  Chunk 1 (2 bytes): {chunk1}")
    print(f"  Chunk 2 (2 bytes): {chunk2}")
    print(f"  Transmitting...")

    # Transmit in two parts
    sys.stdout.write(kitty_cmd("a=t,f=32,s=1,v=1,i=104,m=1", chunk1))
    sys.stdout.write(kitty_cmd("a=t,f=32,i=104,m=0", chunk2))
    # Display
    sys.stdout.write(kitty_cmd("a=p,i=104,c=1,r=1", ""))
    sys.stdout.flush()

    print("  Expected: Magenta pixel above")
    print("  OLD VERSION: Will show error 'could not decode payload'")
    print("  NEW VERSION: Should show magenta pixel")
    print()

def main():
    print()
    print("=" * 60)
    print("Kitty Image Protocol Multi-part Transmission Test")
    print("=" * 60)
    print()
    print("This tests whether iTerm2 correctly handles multipart image")
    print("transmissions where each chunk is base64-encoded independently")
    print("(which may produce padding in non-final chunks).")
    print()
    print("Running tests...")
    print()

    test_single_part()
    time.sleep(0.1)

    test_multipart_stream_encoding()
    time.sleep(0.1)

    test_multipart_independent_encoding()
    time.sleep(0.1)

    test_multipart_many_chunks()
    time.sleep(0.1)

    test_minimal_repro()

    print("=" * 60)
    print("Tests complete!")
    print()
    print("Summary:")
    print("  - Tests 1-2 should pass on all versions")
    print("  - Tests 3-5 test the bug fix (independent chunk encoding)")
    print("    - OLD: These will fail (no image or error)")
    print("    - NEW: These should show the correct colored squares")
    print("=" * 60)
    print()

if __name__ == "__main__":
    main()
