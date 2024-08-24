#!/opt/homebrew/bin/bash

#!/bin/bash

read_expecting_ok() {
    local params=$1
    if [[ -n "$params" ]]; then
        read_expecting $'\e_G'"$params"$'OK\e\\'
    else
        read_expecting $'\e_GOK\e\\'
    fi
}

read_expecting() {
    local expected_response="$1"

    echo ""
    printf "Reading response. Press backslash to stop."
    response=$(read_until_backslash)
    printf "\r\e[K"

    if [[ "$response" == "$expected_response" ]]; then
        echo "Valid response received"
    else
        echo "Unexpected response:"
        replace_controls "$response"
        echo ""
        echo "Expected:"
        echo $(replace_controls "$expected_response")
    fi
}

replace_controls() {
  local input="$1"
  local output=""
  
  for ((i=0; i<${#input}; i++)); do
    char="${input:i:1}"
    ascii=$(printf "%d" "'$char")
    
    if ((ascii >= 0 && ascii <= 31)); then
      output+="^$(printf \\$(printf "%03o" $((ascii + 64))))"
    elif ((ascii == 127)); then
      output+="^?"
    else
      output+="$char"
    fi
  done
  
  printf "%s" "$output"
}

read_until_backslash() {
    # Disable echo and canonical mode
    stty -echo -icanon

    # Initialize an empty string to hold the input
    input=""

    # Read one byte at a time until backslash is found
    while IFS= read -r -n 1 char; do
        input+="$char"
        if [[ $char == '\' ]]; then
            break
        fi
    done

    # Re-enable echo and canonical mode
    stty echo icanon

    # Print the captured input
    printf "%s" "$input"
}

set_underline_color() {
    local r=$1
    local g=$2
    local b=$3
    printf '\e[58;2;%d;%d;%dm' "$r" "$g" "$b"
}

unicode_placeholder() {
  local image_id=$1
  local x=$2
  local y=$3
  local placement_id=$4

  # Diacritic mapping for rows and columns
  # Note: This is a partial mapping for simplicity. You need to extend it based on your requirements.
  local diacritics=(
    "\U0305"  # 0
    "\U030D"  # 1
    "\U030E"  # 2
    "\U0310"  # 3
    "\U0312"  # 4
    "\U033D"  # 5
    "\U033E"  # 6
    "\U033F"  # 7
    "\U0346"  # 8
    "\U034A"  # 9
  )

  # Map x (row) and y (column) to their respective diacritics
  local diacritic_row=${diacritics[$x]}
  local diacritic_col=${diacritics[$y]}

  # Foreground color (image ID)
  if [[ -n "$image_id" ]]; then
    local low_image_id=$((image_id & 0xFFFFFF))
    local fg_color_code="\e[38;5;${low_image_id}m"
    local high_image_id=$(((image_id >> 24) & 0xFF))
    if [[ $high_image_id -ne 0 ]]; then
      local diacritic_image_id=${diacritics[$high_image_id]}
    else
      local diacritic_image_id=""
    fi
  else
    local fg_color_code=""
  fi

  if [[ -n "$placement_id" ]]; then
    local r=$(( (placement_id >> 16) & 0xFF ))
    local g=$(( (placement_id >> 8) & 0xFF ))
    local b=$(( placement_id & 0xFF ))
    local ul_color=$(set_underline_color $r $g $b)
  else
    local ul_color=""
  fi

  # Generate the placeholder using U+10EEEE and the corresponding diacritics for row and column
  printf "${fg_color_code}${ul_color}\U10EEEE${diacritic_row}${diacritic_col}${diacritic_image_id}\e[39;59m"
}

red_bg() {
    printf "\e[41m"
}

reset_sgr() {
    printf "\e[m"
}

goto() {
    local x=$1
    local y=$2
    printf "\e[%s;%sH" $y $x
}

make_compressed_image_data() {
    local width=$1
    local height=$2
    local color=$3

    local total_pixels=$((width * height))
    repeat $color $total_pixels | zlib-flate -compress | base64
}

make_image_data() {
    local width=$1
    local height=$2
    local color=$3

    local total_pixels=$((width * height))
    repeat $color $total_pixels | base64
}

repeat() {
    local color=$1
    local total_pixels=$2
    for ((i = 0; i < total_pixels; i++)); do
        printf "%s" "$color" | xxd -r -p
    done
}

hex_to_binary() {
    local hex_string=$1
    printf "%s" "$hex_string" | xxd -r -p
}
placeholder() {
    local width=$1
    local height=$2
    seq 1 $((width * height))
}

# build_start action
# build_arg key value
# build_arg key value
# build_end payload

build_start() {
    local action=$1
    if [[ -n "$action" ]]; then
        printf "\e_Ga=%s" $action
        export elide_first_comma=0
    else
        printf "\e_G"
        export elide_first_comma=1
    fi
}

build_end() {
    payload=$1
    printf ";%s\e\\" $payload
}

build_arg() {
    key=$1
    value=$2
    if [[ "$elide_first_comma" == "0" ]]; then
        printf ","
    fi
    printf "%s=%s" $key $value
    export elide_first_comma=0
}

build_placeholder_rect() {
  local rows=$1
  local cols=$2
  local image_id=$3
  local placement_id=$4

  printf "  "
  for (( x=0; x<cols; x++ )); do
      printf "%d" $x
  done
  echo ""
  for (( y=0; y<rows; y++ )); do
      printf "%2d" $y
      for (( x=0; x<cols; x++ )); do
          unicode_placeholder "$image_id" $y $x "$placement_id"
      done
      echo "#"
  done
}

test_transmit_display_32bit_direct() {
    local format=32
    local width=10
    local height=15
    local id=1
    local placement_id=100
    local color="ff0000ff"
    build_start T
    build_arg q 1
    build_arg f $format
    build_arg s $width
    build_arg v $height
    build_arg i $id
    build_arg p $placement_id
    build_end $(make_image_data $width $height $color)
}

test_transmit_display_24bit_direct() {
    local format=24
    local width=10
    local height=15
    local id=1
    local placement_id=100
    local color="ff00ff"
    build_start T
    build_arg q 1
    build_arg f $format
    build_arg s $width
    build_arg v $height
    build_arg i $id
    build_arg p $placement_id
    build_end $(make_image_data $width $height $color)
}

test_transmit_display_relative_direct() {
    local format=32
    local width=10
    local height=15
    local id=1
    local placement_id=100
    local color="ff0000ff"
    build_start T
    build_arg q 1
    build_arg f $format
    build_arg s $width
    build_arg v $height
    build_arg i $id
    build_arg p $placement_id
    build_end $(make_image_data $width $height $color)

    local format=32
    local width=30
    local height=50
    local id=2
    local placement_id=101
    local parent_placement=100
    local parent_image=1
    local hdisp=5
    local vdisp=2
    local color="00ff00ff"
    build_start T
    build_arg q 1
    build_arg f $format
    build_arg s $width
    build_arg v $height
    build_arg i $id
    build_arg p $placement_id
    build_arg P $parent_image
    build_arg Q $parent_placement
    build_arg H $hdisp
    build_arg V $vdisp
    build_end $(make_image_data $width $height $color)
}

test_transmit_display_png() {
    local format=100
    build_start T
    build_arg q 1
    build_arg f $format
    build_end $(cat dog.png.txt)
}

test_transmit_direct_png_width_only() {
    local format=100
    local width=200
    build_start T
    build_arg q 1
    build_arg f $format
    build_arg s $width
    build_end $(cat dog.png.txt)
}

test_transmit_direct_rgba_compressed() {
    local format=24
    local width=10
    local height=15
    local id=1
    local placement_id=100
    local color="ff00ff"
    local compression=z
    build_start T
    build_arg q 1
    build_arg f $format
    build_arg s $width
    build_arg v $height
    build_arg i $id
    build_arg p $placement_id
    build_arg o $compression
    build_end $(make_compressed_image_data $width $height $color)
}

first_half() {
    split -n 2 -d "$1" temp_part_
    printf "%s" "$(cat temp_part_00)"
    rm temp_part_00 temp_part_01
}

second_half() {
    split -n 2 -d "$1" temp_part_
    printf "%s" "$(cat temp_part_01)"
    rm temp_part_00 temp_part_01
}

test_chunked_png() {
    local format=100

    build_start T
    build_arg q 1
    build_arg f $format
    build_arg m 1
    build_end $(first_half dog.png.txt)

    build_start T
    build_arg q 1
    build_arg f $format
    build_arg m 0
    build_end $(second_half dog.png.txt)
}

test_transmit_then_place() {
    local format=100
    local id=42

    build_start t
    build_arg q 1
    build_arg f $format
    build_arg i $id
    build_end $(cat dog.png.txt)

    build_start p
    build_arg q 1
    build_arg i $id
    build_end ""
}

test_transmit_by_number_then_place() {
    local format=100
    local number=42

    build_start t
    build_arg f $format
    build_arg I $number
    build_end $(cat dog.png.txt)
    read_expecting $'\e_Gi=1,I=42;OK\e\\'

    local id=1
    build_start p
    build_arg q 1
    build_arg i $id
    build_end ""
}

test_cursor_doesnt_move() {
    local format=100

    build_start T
    build_arg q 1
    build_arg f $format
    build_arg C 0
    build_end $(cat dog.png.txt)
    echo "0"

    build_start T
    build_arg q 1
    build_arg f $format
    build_arg C 1
    build_end $(cat dog.png.txt)
    printf "1"
}

test_source_rect() {
    local format=100
    build_start T
    build_arg q 1
    build_arg f $format
    build_arg x 20
    build_arg y 20
    build_arg w 20
    build_arg h 20
    build_end $(cat dog.png.txt)
}

test_upscale() {
    local format=100
    local cols=20
    local rows=20
    build_start T
    build_arg q 1
    build_arg f $format
    build_arg c $cols
    build_arg r $rows
    build_end $(cat dog.png.txt)
}

test_z_index_image_behind_bg() {
    local format=100
    build_start T
    build_arg q 1
    build_arg f $format
    build_arg z -2000000000
    build_end $(cat dog.png.txt)
    goto 1 3
    red_bg
    printf "xxxxxx"
}

test_z_index_image_behind_bg() {
    local format=100
    build_start T
    build_arg q 1
    build_arg f $format
    build_arg z -2000000000
    build_end $(cat dog.png.txt)
    goto 1 3
    red_bg
    echo "xxxxxx"
    reset_sgr
    echo "xxxxxx"
}

test_z_index_image_behind_text() {
    local format=100
    build_start T
    build_arg q 1
    build_arg f $format
    build_arg z -1000000000
    build_end $(cat dog.png.txt)
    goto 1 3
    red_bg
    echo "xxxxxx"
    reset_sgr
    echo "xxxxxx"
}

test_z_index_image_in_front_of_text() {
    local format=100
    build_start T
    build_arg q 1
    build_arg f $format
    build_arg z 1
    build_end $(cat dog.png.txt)
    goto 1 3
    red_bg
    echo "xxxxxx"
    reset_sgr
    echo "xxxxxx"
}

test_z_index_0() {
    local format=100
    build_start T
    build_arg q 1
    build_arg f $format
    build_arg z 1
    build_end $(cat dog.png.txt)
    goto 1 3
    red_bg
    echo "xxxxxx"
    reset_sgr
    echo "xxxxxx"
}

test_unicode_placeholder_image_id() {
    local image_id=99

    # Transfer an image
    local format=100
    build_start t
    build_arg q 1
    build_arg f $format
    build_arg i $image_id
    build_end $(cat dog.png.txt)

    # Put a virtual placement
    local format=100
    local cols=5
    local rows=5

    build_start p
    build_arg q 1
    build_arg f $format
    build_arg U 1
    build_arg i $image_id
    build_arg c $cols
    build_arg r $rows
    build_end $(cat dog.png.txt)

    build_placeholder_rect $rows $cols $image_id ""
}

test_unicode_placeholder_image_id_bg_color() {
    local image_id=99

    # Transfer an image
    local format=100
    build_start t
    build_arg q 1
    build_arg f $format
    build_arg i $image_id
    build_end $(cat dog.png.txt)

    # Put a virtual placement
    local format=100
    local cols=5
    local rows=5

    build_start p
    build_arg q 1
    build_arg f $format
    build_arg U 1
    build_arg i $image_id
    build_arg c $cols
    build_arg r $rows
    build_end $(cat dog.png.txt)

    red_bg
    build_placeholder_rect $rows $cols $image_id ""
    reset_sgr
  }


test_unicode_placeholder_image_id_32bit() {
    # 38;5;42m u+10eee u+0305 u+0305 u+030e
    local image_id=33554474

    # Transfer an image
    local format=100
    build_start t
    build_arg q 1
    build_arg f $format
    build_arg i $image_id
    build_end $(cat dog.png.txt)

    # Put a virtual placement
    local format=100
    local cols=5
    local rows=5

    build_start p
    build_arg q 1
    build_arg f $format
    build_arg U 1
    build_arg i $image_id
    build_arg c $cols
    build_arg r $rows
    build_end $(cat dog.png.txt)

    build_placeholder_rect $rows $cols $image_id ""
}

test_unicode_placeholder_placement_id() {
    local image_id=99

    # Transfer an image
    local format=100
    build_start t
    build_arg q 1
    build_arg f $format
    build_arg i $image_id
    build_end $(cat dog.png.txt)

    # Put a virtual placement
    local format=100
    local cols=5
    local rows=5
    local placement_id=42

    build_start p
    build_arg q 1
    build_arg f $format
    build_arg U 1
    build_arg i $image_id
    build_arg p $placement_id
    build_arg c $cols
    build_arg r $rows
    build_end $(cat dog.png.txt)

    # Print placeholders with placeholder IDs
    build_placeholder_rect $rows $cols $image_id $placement_id
}

test_delete_image_id() {
    local image_id=99

    # Transfer an image
    local format=100
    build_start t
    build_arg q 1
    build_arg f $format
    build_arg i $image_id
    build_end $(cat dog.png.txt)

    # Place the image
    build_start p
    build_arg q 1
    build_arg i $image_id
    build_end ""

    sleep 1

    # Delete the image
    build_start d
    build_arg q 1
    build_arg d i
    build_arg i $image_id
    build_end ""
}

test_delete_placement_id() {
    local image_id=99

    # Transfer an image
    local format=100
    build_start t
    build_arg q 1
    build_arg f $format
    build_arg i $image_id
    build_end $(cat dog.png.txt)

    # Place the image
    local placement_id=42
    build_start p
    build_arg q 1
    build_arg i $image_id
    build_arg p $placement_id
    build_end ""

    sleep 1

    # Delete the image
    build_start d
    build_arg q 1
    build_arg d i
    build_arg i $image_id
    build_arg p $placement_id
    build_end ""
}

# Kitty seems to do the wrong thing here.
test_delete_newest_image() {
    # Transfer an image
    local format=100
    build_start T
    build_arg q 1
    build_arg f $format
    build_arg I 1
    build_end $(cat dog.png.txt)

    # Transfer another image
    local format=100
    build_start T
    build_arg q 1
    build_arg f $format
    build_arg I 1
    build_end $(cat cat.png.txt)

    sleep 1

    # Delete newest image with id $image_id (the cat)
    build_start d
    build_arg q 1
    build_arg d n
    build_arg I 1
    build_end ""
}

test_delete_cursor_intersecting() {
    local image_id=99

    # Transfer an image
    local format=100
    build_start T
    build_arg q 1
    build_arg f $format
    build_arg i $image_id
    build_end $(cat dog.png.txt)

    # Transfer an image
    local format=100
    build_start T
    build_arg q 1
    build_arg f $format
    build_arg i $image_id
    build_end $(cat cat.png.txt)

    goto 2 2

    sleep 1

    # Delete the dog
    build_start d
    build_arg q 1
    build_arg d c
    build_end ""
}

test_delete_cell_intersecting() {
    local image_id=98


    echo "Send two images"

    # Transfer an image
    local format=100
    build_start T
    build_arg q 1
    build_arg f $format
    build_arg i $image_id
    build_end $(cat dog.png.txt)

    # Transfer an image
    local format=100
    local image_id=99
    build_start T
    build_arg q 1
    build_arg f $format
    build_arg i $image_id
    build_end $(cat cat.png.txt)

    echo ""
    echo "Sleep"
    sleep 1

    echo "Delete dog"
    # Delete the dog
    build_start d
    build_arg q 1
    build_arg d p
    build_arg x 3
    build_arg y 3
    build_end ""
}

test_delete_cell_zindex_intersecting() {

    # Transfer an image
    goto 1 2
    local format=100
    local image_id=1
    build_start T
    build_arg q 1
    build_arg f $format
    build_arg i $image_id
    build_arg z 2
    build_end $(cat dog.png.txt)

    # Transfer an image
    local format=100
    local image_id=2
    goto 2 3
    build_start T
    build_arg q 1
    build_arg f $format
    build_arg i $image_id
    build_arg z 1
    build_end $(cat cat.png.txt)

    sleep 1

    # Delete the dog
    build_start d
    build_arg q 1
    build_arg d q
    build_arg x 3
    build_arg y 3
    build_arg z 2
    build_end ""
}

test_delete_image_range() {
    local format=100

    build_start T
    build_arg q 1
    build_arg f $format
    build_arg i 1
    build_end $(cat dog.png.txt)
    echo ""

    build_start T
    build_arg q 1
    build_arg f $format
    build_arg i 2
    build_end $(cat dog.png.txt)
    echo ""

    build_start T
    build_arg q 1
    build_arg f $format
    build_arg i 3
    build_end $(cat dog.png.txt)
    echo ""

    build_start T
    build_arg q 1
    build_arg f $format
    build_arg i 100
    build_end $(cat dog.png.txt)
    echo ""

    sleep 1

    # Delete images 2...99
    build_start d
    build_arg q 1
    build_arg d r
    build_arg x 2
    build_arg y 99
    build_end ""
}

test_delete_column_intersecting() {

    # Transfer an image
    goto 1 2
    local format=100
    local image_id=1
    build_start T
    build_arg q 1
    build_arg f $format
    build_arg i $image_id
    build_end $(cat dog.png.txt)

    # Transfer an image
    goto 10 2
    local format=100
    local image_id=2
    build_start T
    build_arg q 1
    build_arg f $format
    build_arg i $image_id
    build_end $(cat cat.png.txt)

    # Transfer an image
    goto 12 10
    local format=100
    local image_id=3
    build_start T
    build_arg q 1
    build_arg f $format
    build_arg i $image_id
    build_end $(cat cat.png.txt)

    sleep 1

    # Delete the second two
    build_start d
    build_arg q 1
    build_arg d x
    build_arg x 13
    build_end ""
}

test_delete_row_intersecting() {
    local image_id=99

    # Transfer an image
    goto 1 2
    local format=100
    build_start T
    build_arg q 1
    build_arg f $format
    build_arg i $image_id
    build_end $(cat dog.png.txt)

    # Transfer an image
    goto 10 2
    local format=100
    build_start T
    build_arg q 1
    build_arg f $format
    build_arg i $image_id
    build_end $(cat cat.png.txt)

    # Transfer an image
    goto 12 10
    local format=100
    build_start T
    build_arg q 1
    build_arg f $format
    build_arg i $image_id
    build_end $(cat cat.png.txt)

    sleep 1

    # Delete the first two
    build_start d
    build_arg q 1
    build_arg d y
    build_arg y 3
    build_end ""
}

# Kitty seems to have a bug with this
test_delete_zindex() {
    local image_id=99

    # Transfer an image
    goto 1 2
    local format=100
    build_start T
    build_arg q 1
    build_arg f $format
    build_arg i $image_id
    build_arg z 1
    build_end $(cat dog.png.txt)

    # Transfer an image
    goto 10 2
    local format=100
    build_start T
    build_arg q 1
    build_arg f $format
    build_arg i $image_id
    build_arg z 2
    build_end $(cat cat.png.txt)

    # Transfer an image
    goto 12 10
    local format=100
    build_start T
    build_arg q 1
    build_arg f $format
    build_arg i $image_id
    build_arg z 3
    build_end $(cat cat.png.txt)

    sleep 1

    # Delete the second one
    build_start d
    build_arg q 1
    build_arg d z
    build_arg z 2
    build_end ""
}

test_dangling_image() {
    local image_id=1

    # Transfer an image
    goto 1 2

    echo Sending image
    local format=100
    build_start T
    build_arg q 1
    build_arg f $format
    build_arg i $image_id
    build_arg z 1
    build_end $(cat dog.png.txt)

    echo ""
    echo sleeping
    sleep 1

    echo delete all placements
    # Delete all visible placements
    build_start d
    build_arg q 1
    build_arg d a
    build_end ""

    echo ""
    echo sleeping
    sleep 1

    echo add placement for image
    # Add a placement for the image
    build_start p
    build_arg q 1
    build_arg i $image_id
    build_end ""
}

test_success_response_T() {
    local format=100
    build_start T
    build_arg f $format
    build_end $(cat dog.png.txt)

    read_expecting_ok
}

test_error_response_T() {
    local format=24
    local width=10
    local height=15
    local id=1
    local placement_id=100
    local color="ff00ff"
    build_start T
    build_arg q 1
    build_arg f $format
    build_arg s $width
    build_arg v $height
    build_arg i $id
    build_arg p $placement_id
    # Send 1x1 data even though we said it would be 10x15
    build_end $(make_image_data 1 1 $color)

    read_expecting $'\e_Gi=1,p=100;invalid payload\e\\'
}

test_error_response_p() {
    local id=99

    build_start p
    build_arg i $id
    build_end ""

    read_expecting $'\e_Gi=99;ENOENT:Put command refers to non-existent image with id: 99 and number: 0\e\\'
}

test_success_response_p() {
    local id=99

    build_start t
    build_arg f 100
    build_arg i $id
    build_arg q 1
    build_end $(cat dog.png.txt)

    build_start p
    build_arg i $id
    build_end ""

    read_expecting_ok "i=$id;"
}

test_shared_memory_fails() {
    build_start ""
    build_arg i 31
    build_arg s 10
    build_arg v 2
    build_arg t s
    build_end $(printf "/bogus/path" | base64)

    read_expecting $'\e_Gi=31;EBADF:Unimplemented\e\\'
}

run_test() {
    printf "\e[m\e[2J\e[H\e_Ga=d\e\\"
    local name=$1
    echo "Running $name"
    $name
    printf "\e[m\e[H\e[100B%s finished. " "$name"
    read -p "Press return to continue"
}
    

tests=($(declare -F | awk '{print $3}' | grep '^test_'))

# Check if an argument is provided
if [ -n "$1" ]; then
    regex="$1"
else
    regex=".*"  # Match all if no argument is provided
fi

# Iterate over the list and call each function
for func in "${tests[@]}"; do
    if [[ $func =~ $regex ]]; then
        run_test $func
    fi
done
