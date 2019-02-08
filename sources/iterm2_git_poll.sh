#!/bin/sh

GIT_BINARY=/usr/bin/git

dirty() {
    # Outputs "dirty" or "clean"
    OUTPUT=$("$GIT_BINARY" status --porcelain --ignore-submodules -unormal)
    if (($?)); then
        echo "clean"
        return
    fi
    if [ -z "$OUTPUT" ]; then
        echo "clean"
    else
        echo "dirty"
    fi
}

counts() {
    OUTPUT=$("$GIT_BINARY" rev-list --left-right --count HEAD...@'{u}' 2>/dev/null)
    if (($?)); then
        return
    fi
    echo "$OUTPUT"
}

branch() {
    OUTPUT=$("$GIT_BINARY" symbolic-ref -q --short HEAD || git rev-parse --short HEAD)
    if (($?)); then
        return
    fi
    echo "$OUTPUT"
}

git_poll () {
    DIRECTORY="$1"
    cd "$DIRECTORY"
    DIRTY=$(dirty)
    COUNTS=$(counts)
    PUSH_COUNT=$(cut -f1 <<< "$COUNTS")
    PULL_COUNT=$(cut -f2 <<< "$COUNTS")
    BRANCH=$(branch)

    echo "--BEGIN--"
    echo "DIRECTORY: $DIRECTORY"
    echo "DIRTY: $DIRTY"
    echo "PUSH: $PUSH_COUNT"
    echo "PULL: $PULL_COUNT"
    echo "BRANCH: $BRANCH"
    echo "--END--"
    echo ""
}


while read line
do
    git_poll "$line"
done

