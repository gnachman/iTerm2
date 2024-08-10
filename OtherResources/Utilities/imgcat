#!/usr/bin/env bash

set -o pipefail

# tmux requires unrecognized OSC sequences to be wrapped with DCS tmux;
# <sequence> ST, and for all ESCs in <sequence> to be replaced with ESC ESC. It
# only accepts ESC backslash for ST. We use TERM instead of TMUX because TERM
# gets passed through ssh.
function print_osc() {
    if [[ $TERM == screen* || $TERM == tmux* ]]; then
        printf "\033Ptmux;\033\033]"
    else
        printf "\033]"
    fi
}

# More of the tmux workaround described above.
function print_st() {
    if [[ $TERM == screen* || $TERM == tmux* ]]; then
        printf "\a\033\\"
    else
        printf "\a"
    fi
}

function load_version() {
    if [ -z ${IMGCAT_BASE64_VERSION+x} ]; then
        IMGCAT_BASE64_VERSION=$(base64 --version 2>&1)
        export IMGCAT_BASE64_VERSION
    fi
}

function b64_encode() {
    load_version
    if [[ $IMGCAT_BASE64_VERSION =~ GNU ]]; then
        # Disable line wrap
        base64 -w0
    else
        base64
    fi
}

function b64_decode() {
    load_version
    if [[ $IMGCAT_BASE64_VERSION =~ fourmilab ]]; then
        BASE64ARG=-d
    elif [[ $IMGCAT_BASE64_VERSION =~ GNU ]]; then
        BASE64ARG=-di
    else
        BASE64ARG=-D
    fi
    base64 $BASE64ARG
}

# print_image filename inline base64contents print_filename width height preserve_aspect_ratio
#   filename: Filename to convey to client
#   inline: 0 or 1, if set to 1, the file will be displayed inline, otherwise, it will be downloaded
#   base64contents: Base64-encoded contents
#   print_filename: 0 or 1, if set to 1, print the filename after outputting the image
#   width: set output width of the image in character cells, pixels or percent
#   height: set output height of the image in character cells, pixels or percent
#   preserve_aspect_ratio: 0 or 1, if set to 1, fill the specified width and height as much as possible without stretching the image
#   file: Empty string or file type like "application/json" or ".js".
#   legacy: 1 to send one giant control sequence, 0 to send many small control sequences.
function print_image() {
    # Send metadata to begin transfer.
    print_osc
    printf "1337;"
    if [[ "$9" -eq 1 ]]; then
        printf "File"
    else
        printf "MultipartFile"
    fi
    printf "=inline=%s" "$2"
    printf ";size=%d" $(printf "%s" "$3" | b64_decode | wc -c)
    [ -n "$1" ] && printf ";name=%s" "$(printf "%s" "$1" | b64_encode)"
    [ -n "$5" ] && printf ";width=%s" "$5"
    [ -n "$6" ] && printf ";height=%s" "$6"
    [ -n "$7" ] && printf ";preserveAspectRatio=%s" "$7"
    [ -n "$8" ] && printf ";type=%s" "$8"
    if [[ "$9" -eq 1 ]]; then
        printf ":%s" "$3"
        print_st
    else
        print_st

        # Split into 200-byte chunks. This helps it get through tmux.
        parts=$(printf "%s" "$3" | fold -w 200)

        # Send each part.
        for part in $parts; do
            print_osc
            printf '1337;FilePart=%s' "$part"
            print_st
        done

        # Indicate completion
        print_osc
        printf '1337;FileEnd'
        print_st
    fi

    printf '\n'
    [ "$4" == "1" ] && echo "$1"
    has_image_displayed=t
}

function error() {
    errcho "ERROR: $*"
}

function errcho() {
    echo "$@" >&2
}

function show_help() {
    errcho
    errcho "Usage: imgcat [-p] [-n] [-W width] [-H height] [-r] [-s] [-u] [-t file-type] [-f] filename ..."
    errcho "       cat filename | imgcat [-W width] [-H height] [-r] [-s]"
    errcho
    errcho "Display images inline in the iTerm2 using Inline Images Protocol"
    errcho
    errcho "Options:"
    errcho
    errcho "    -h, --help                      Display help message"
    errcho "    -p, --print                     Enable printing of filename or URL after each image"
    errcho "    -n, --no-print                  Disable printing of filename or URL after each image"
    errcho "    -u, --url                       Interpret following filename arguments as remote URLs"
    errcho "    -f, --file                      Interpret following filename arguments as regular Files"
    errcho "    -t, --type file-type            Provides a type hint"
    errcho "    -r, --preserve-aspect-ratio     When scaling image preserve its original aspect ratio"
    errcho "    -s, --stretch                   Stretch image to specified width and height (this option is opposite to -r)"
    errcho "    -W, --width N                   Set image width to N character cells, pixels or percent (see below)"
    errcho "    -H, --height N                  Set image height to N character cells, pixels or percent (see below)"
    errcho "    -l, --legacy                    Use legacy protocol that sends the whole image in a single control sequence"
    errcho
    errcho "    If you don't specify width or height an appropriate value will be chosen automatically."
    errcho "    The width and height are given as word 'auto' or number N followed by a unit:"
    errcho "        N      character cells"
    errcho "        Npx    pixels"
    errcho "        N%     percent of the session's width or height"
    errcho "        auto   the image's inherent size will be used to determine an appropriate dimension"
    errcho
    errcho "    If a type is provided, it is used as a hint to disambiguate."
    errcho "    The file type can be a mime type like text/markdown, a language name like Java, or a file extension like .c"
    errcho "    The file type can usually be inferred from the extension or its contents. -t is most useful when"
    errcho "    a filename is not available, such as whe input comes from a pipe."
    errcho
    errcho "Examples:"
    errcho
    errcho "    $ imgcat -W 250px -H 250px -s avatar.png"
    errcho "    $ cat graph.png | imgcat -W 100%"
    errcho "    $ imgcat -p -W 500px -u http://host.tld/path/to/image.jpg -W 80 -f image.png"
    errcho "    $ cat url_list.txt | xargs imgcat -p -W 40 -u"
    errcho "    $ imgcat -t application/json config.json"
    errcho
}

function check_dependency() {
    if ! (builtin command -V "$1" >/dev/null 2>&1); then
        error "missing dependency: can't find $1"
        exit 1
    fi
}

# verify that value is in the image sizing unit format: N / Npx / N% / auto
function validate_size_unit() {
    if [[ ! "$1" =~ ^(:?[0-9]+(:?px|%)?|auto)$ ]]; then
        error "Invalid image sizing unit - '$1'"
        show_help
        exit 1
    fi
}

## Main

if [ -t 0 ]; then
    has_stdin=f
else
    has_stdin=t
fi

# Show help if no arguments and no stdin.
if [ $has_stdin = f ] && [ $# -eq 0 ]; then
    show_help
    exit
fi

check_dependency base64
check_dependency wc
file_type=""
legacy=0

# Look for command line flags.
while [ $# -gt 0 ]; do
    case "$1" in
    -h | --h | --help)
        show_help
        exit
        ;;
    -p | --p | --print)
        print_filename=1
        ;;
    -n | --n | --no-print)
        print_filename=0
        ;;
    -W | --W | --width)
        validate_size_unit "$2"
        width="$2"
        shift
        ;;
    -H | --H | --height)
        validate_size_unit "$2"
        height="$2"
        shift
        ;;
    -r | --r | --preserve-aspect-ratio)
        preserve_aspect_ratio=1
        ;;
    -s | --s | --stretch)
        preserve_aspect_ratio=0
        ;;
    -l | --l | --legacy)
        legacy=1
        ;;
    -f | --f | --file)
        has_stdin=f
        is_url=f
        ;;
    -u | --u | --url)
        check_dependency curl
        has_stdin=f
        is_url=t
        ;;
    -t | --t | --type)
         file_type="$2"
         shift
         ;;
    -*)
        error "Unknown option flag: $1"
        show_help
        exit 1
        ;;
    *)
        if [ "$is_url" == "t" ]; then
            encoded_image=$(curl -fs "$1" | b64_encode) || {
                error "Could not retrieve image from URL $1, error_code: $?"
                exit 2
            }
        elif [ -r "$1" ]; then
            encoded_image=$(cat "$1" | b64_encode)
        else
            error "imgcat: $1: No such file or directory"
            exit 2
        fi
        has_stdin=f
        print_image "$1" 1 "$encoded_image" "$print_filename" "$width" "$height" "$preserve_aspect_ratio" "$file_type" "$legacy"
        ;;
    esac
    shift
done

# Read and print stdin
if [ $has_stdin = t ]; then
    print_image "" 1 "$(cat | b64_encode)" 0 "$width" "$height" "$preserve_aspect_ratio" "$file_type" "$legacy"
fi

if [ "$has_image_displayed" != "t" ]; then
    error "No image provided. Check command line options."
    show_help
    exit 1
fi

exit 0
