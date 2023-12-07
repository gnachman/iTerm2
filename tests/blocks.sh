#!/usr/bin/env bash

start_block() {
  block_id="$1"
  type="$2"
  echo -ne "\033]1337;Block=attr=start;id=$block_id;type=$type\a"
}

end_block() {
  block_id="$1"
  echo -ne "\033]1337;Block=attr=end;id=$block_id;render=0\a"
}

copyButton() {
  block_id="$1"
  echo -ne "\033]1337;Button=type=copy;block=$block_id\a"
}

block_id=$(uuidgen)
block_type='python'

content="print('$block_id')"

echo $(copyButton $block_id)
echo -n $(start_block $block_id $block_type)
echo $content
# With `-n` it will copy the next line (typically a PS1 / prompt)
# Without `-n` it won't copy the prompt but it will print an extra line
echo -n $(end_block $block_id)
