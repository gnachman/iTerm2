#!/opt/homebrew/bin/bash

#!/bin/bash

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

emit_chunks() {
    local data="$1"
    local chunk_size=1024
    local total_length=${#data}
    local index=0

    while [ $index -lt $total_length ]; do
        local chunk="${data:$index:$chunk_size}"
        index=$((index + chunk_size))

        if [ $index -lt $total_length ]; then
            emit "$chunk" 1
        else
            emit "$chunk" 0
        fi
    done
}

emit() {
    build_start T
    build_arg q 1
    build_arg f 100
    build_arg m $2
    build_arg i $(date +%s)
    build_end $1
}

emit_chunks $(base64 < $1)

