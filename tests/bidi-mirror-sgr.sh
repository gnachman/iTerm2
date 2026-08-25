#!/bin/bash
#
# Mirroring + SGR stress test.
#
# Puts color changes right around each bidi-mirrorable character so the mark
# lands in its own attribute run. The bidi reorder and the mirror decision are
# computed from code points (color-agnostic), but the DRAWING path segments a
# line by color, so this checks that per-cell mirroring still applies when the
# mark is isolated in its own foreground/background run.
#
# Requires "right-to-left text support" ON. Run with the GPU (Metal) renderer
# both on and off; they must match. Compare against a build without mirroring
# (master): the marks below should reverse there and read correctly here.
#
# What to watch for:
#   - a mark that stops mirroring once it has its own color (draw path keyed
#     off the wrong run),
#   - the mark drawn in the wrong color or wrong cell,
#   - the mark's color/mirror differing between the CG and Metal renderers.

esc=$(printf '\033')
rst="${esc}[0m"
red="${esc}[31m"
grn="${esc}[32m"
onred="${esc}[41m"
onblu="${esc}[44m"

# Emit "<pre><color><mark><rst><word><color><mark><rst><post>" so each mark is
# its own foreground run, with Persian text on both sides so the marks mirror.
pair() {  # $1=open $2=close $3=color-label $4=color
    printf '%s  متن %s%s%sتهران%s%s%s شهر\n' "$3" "$4" "$1" "$rst" "$4" "$2" "$rst"
}

echo "=== marks in their own FOREGROUND color run ==="
pair '(' ')' 'parens :' "$red"
pair '[' ']' 'bracket:' "$red"
pair '{' '}' 'brace  :' "$red"
pair '<' '>' 'angle  :' "$red"
pair '«' '»' 'guillmt:' "$red"

echo
echo "=== marks on their own BACKGROUND color run (selection-like) ==="
pair '(' ')' 'parens :' "$onblu"
pair '<' '>' 'angle  :' "$onblu"

echo
echo "=== color change in the MIDDLE of the bracketed span ==="
# open paren red, word half green half default, close paren red.
printf 'متن %s(%s%sته%sران%s)%s شهر\n' "$red" "$rst" "$grn" "$rst" "$red" "$rst"

echo
echo "=== math operator (the case that needs the fix) in its own color ==="
printf 'عدد %s≤%s مقدار\n' "$red" "$rst"

echo
echo "=== whole bracketed group one color, surroundings another ==="
printf '%sمتن %s(تهران)%s شهر%s\n' "$grn" "$red" "$grn" "$rst"

echo
echo "=== CONTROL: English parens in color must NOT mirror ==="
printf 'مرورگر %s(Google)%s را باز کن\n' "$red" "$rst"
