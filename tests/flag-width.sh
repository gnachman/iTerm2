#!/bin/zsh --no-rcs
# Manual check for issue 13070: a flag emoji must occupy two columns, so the
# closing bracket lands immediately after it with no gap.
echo
echo "each pair of brackets should hug its emoji:"
print -r "[🇺🇸]"
print -r "[🙂]"
print -r "[🇺🇸🇫🇷]"
print -r "[🏴󠁧󠁢󠁳󠁣󠁴󠁿]"
print -r "[👨‍👩‍👦]"
echo
echo "a lone regional indicator is two columns:"
print -r "[🇺]"
