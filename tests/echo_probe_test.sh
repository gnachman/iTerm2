#!/bin/bash

unset PASSWORD
unset CHARCOUNT

echo -n "Enter password: "

stty -echo

CHARCOUNT=0
while IFS= read -p "$PROMPT" -r -s -n 1 CHAR
do
    # Enter - accept password
    if [[ $CHAR == $'\0' ]] ; then
        break
    fi
    # Backspace
    if [[ $CHAR == $'\177' ]] ; then
        if [ $CHARCOUNT -gt 0 ] ; then
            CHARCOUNT=$((CHARCOUNT-1))
            PROMPT=$'\b \b'
# Alternate way of erasing a character that the echo probe understands:
#            PROMPT=$'[D[K'
            PASSWORD="${PASSWORD%?}"
        else
            PROMPT=''
        fi
    else
        CHARCOUNT=$((CHARCOUNT+1))
        PROMPT='*'
        PASSWORD+="$CHAR"
    fi
done

stty echo

echo ""
echo Your password is:
echo $PASSWORD

