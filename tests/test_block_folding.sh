#!/bin/bash

# Test script for block folding/unfolding feature
# This creates a block with text, folds it, then unfolds it

BLOCK_ID=$(uuidgen)

echo "Testing block folding with block ID: $BLOCK_ID"
echo ""

# Start a block (matches format from tests/blocks.sh)
echo -ne "\033]1337;Block=attr=start;id=$BLOCK_ID;type=python\a"

# Add some content to the block
echo "=== Block Content Start ==="
echo "Line 1: This is inside the block"
echo "Line 2: More content here"
echo "Line 3: Even more content"
echo "Line 4: Almost done"
echo "Line 5: Last line of block"
echo "=== Block Content End ==="

# End the block
echo -ne "\033]1337;Block=attr=end;id=$BLOCK_ID;render=0\a"

echo ""
echo "Block created. Sleeping for 2 seconds..."
sleep 2

# Fold the block
echo "Folding block..."
echo -ne "\033]1337;UpdateBlock=id=$BLOCK_ID;action=fold\a"

echo "Block folded. Sleeping for 2 seconds..."
sleep 2

# Unfold the block
echo "Unfolding block..."
echo -ne "\033]1337;UpdateBlock=id=$BLOCK_ID;action=unfold\a"

echo "Block unfolded. Test complete!"
