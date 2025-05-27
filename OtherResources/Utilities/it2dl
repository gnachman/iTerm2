#!/bin/bash

if [ $# -lt 1 ]; then
  echo "Usage: $(basename $0) file|directory ..."
  exit 1
fi

# Create tar.gz archive directly to stdout
create_archive() {
    source_dir="$1"
    # Use tar with gzip compression, output to stdout
    # Suppress stderr to avoid noise, let caller handle failure detection
    tar -czf - -C "$(dirname -- "$source_dir")" "$(basename -- "$source_dir")" 2>/dev/null
}

# tmux requires unrecognized OSC sequences to be wrapped with DCS tmux;
# <sequence> ST, and for all ESCs in <sequence> to be replaced with ESC ESC. It
# only accepts ESC backslash for ST. We use TERM instead of TMUX because TERM
# gets passed through ssh.
print_osc() {
    case "$TERM" in
        screen*|tmux*)
            printf "\033Ptmux;\033\033]"
            ;;
        *)
            printf "\033]"
            ;;
    esac
}

# More of the tmux workaround described above.
print_st() {
    case "$TERM" in
        screen*|tmux*)
            printf "\a\033\\"
            ;;
        *)
            printf "\a"
            ;;
    esac
}

load_version() {
    if [ -z "$IT2DL_BASE64_VERSION" ]; then
        export IT2DL_BASE64_VERSION=$(base64 --version 2>&1)
    fi
}

b64_encode() {
    load_version
    case "$IT2DL_BASE64_VERSION" in
        *GNU*)
            # Disable line wrap
            base64 -w0
            ;;
        *)
            base64
            ;;
    esac
}

send_file_data() {
    filename="$1"
    data_source="$2"  # either file path or "-" for stdin
    file_size="$3"
    is_b64_encoded="$4"  # "yes" if data is already base64-encoded, anything else if not
    
    case "$TERM" in
        screen*|tmux*)
            print_osc
            printf '1337;MultipartFile=name=%s;' $(echo -n "$filename" | b64_encode)
            printf "size=%d" "$file_size"
            print_st
            
            if [ "$is_b64_encoded" = "yes" ]; then
                # Data is already base64-encoded, just chunk it
                if [ "$data_source" = "-" ]; then
                    parts=$(fold -w 200)
                else
                    parts=$(fold -w 200 < "$data_source")
                fi
            elif [ "$data_source" = "-" ]; then
                parts=$(b64_encode | fold -w 200)
            else
                parts=$(b64_encode < "$data_source" | fold -w 200)
            fi
            
            for part in $parts; do
                print_osc
                printf '1337;FilePart=%s' "$part"
                print_st
            done
            print_osc
            printf '1337;FileEnd'
            print_st
            ;;
        *)
            printf '\033]1337;File=name=%s;' $(echo -n "$filename" | b64_encode)
            printf "size=%d:" "$file_size"
            if [ "$is_b64_encoded" = "yes" ]; then
                # Data is already base64-encoded, output as-is
                if [ "$data_source" = "-" ]; then
                    cat
                else
                    cat "$data_source"
                fi
            elif [ "$data_source" = "-" ]; then
                b64_encode
            else
                b64_encode < "$data_source"
            fi
            printf '\a'
            ;;
    esac
}

send_file() {
    filepath="$1"
    file_size=$(wc -c < "$filepath")
    send_file_data "$(basename -- "$filepath")" "$filepath" "$file_size" "no"
}

for fn in "$@"
do
    if [ -r "$fn" ]; then
        if [ -d "$fn" ]; then
            # Check for tar
            if ! command -v tar >/dev/null 2>&1; then
                echo "Error: tar command not found. Cannot download directory: $fn" >&2
                continue
            fi
            
            archive_name="$(basename -- "$fn").tar.gz"
            
            # Create archive, base64-encode immediately to avoid binary data in variables
            if archive_b64=$(create_archive "$fn" | b64_encode) && [ -n "$archive_b64" ]; then
                # Calculate original file size by decoding base64
                archive_size=$(printf '%s' "$archive_b64" | base64 -d | wc -c)
                # Send pre-encoded data via stdin - data is already base64-encoded
                printf '%s' "$archive_b64" | send_file_data "$archive_name" "-" "$archive_size" "yes"
            else
                echo "Error: Failed to create tar.gz archive for directory: $fn" >&2
                continue
            fi
        else
            # Handle regular file
            send_file "$fn"
        fi
    else
        echo "File or directory $fn does not exist or is not readable." >&2
    fi
done
