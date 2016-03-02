#!/bin/bash
read_bytes()
{
  numbytes=$1
  dd bs=1 count=$numbytes 2>/dev/null
}

ordinal_for_next_byte_of_input()
{
  c=$(read_bytes 1)
  echo -n $c | od -t u1 -A n | sed -e 's/^ *//' | sed -e 's/  / /g' | sed -e 's/ *$//' | head -1
}

echo -n ']1337;CustomView='
echo -n '{ "app": "WebView", "arguments": { "url": "'"$1"'" } }' | base64
echo -n ''


_STTY=$(stty -g)      ## Save current terminal setup
stty -echo -icanon raw    ## Turn off line buffering

# Wait for will show

echo ']0;Waiting for will show '
while [ $(ordinal_for_next_byte_of_input) -ne 7 ]; do
  true
done

# Wait for did show
echo ']0;Waiting for did show '
while [ $(ordinal_for_next_byte_of_input) -ne 7 ]; do
  true
done

stty "$_STTY"            ## Restore terminal settings

