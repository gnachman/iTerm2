#!/usr/bin/env sh

GIT_BINARY=$(command -v git)
NICE="/usr/bin/nice -n 20"
PRIORITY=20

xcode() {
    # Check if git is broken because it can't find Xcode. A special charm of macOS for you.
    local output=$($NICE "${GIT_BINARY}" --version 2>&1)
    # if there's no error, then return nothing
    if ! egrep -q "xcrun: error|xcodebuild -license" <<< "${output}"; then
        echo ""
        return
    fi
    tr '\n' '\t' <<< "${output}"
}

dirty() {
    # Outputs "dirty" or "clean"
    local output=$($NICE "${GIT_BINARY}" status --porcelain --ignore-submodules -unormal 2>/dev/null)
    # if we get a non-zero exit code, or the output is empty, then we consider it "clean"
    if [ $? -ne 0 ] || [ -z "${output}" ]; then
        echo "clean"
    else
        echo "dirty"
    fi
}

counts() {
    local output=$($NICE "${GIT_BINARY}" rev-list --left-right --count HEAD...@'{u}' 2>/dev/null)
    if [ $? -ge 1 ]; then
        echo "error"
    else
        echo "${output}"
    fi
}

branch() {
    local output=$($NICE "${GIT_BINARY}" symbolic-ref -q --short HEAD 2>/dev/null || git rev-parse --short HEAD)
    if [ $? -eq 0 ]; then
        echo "${output}"
    fi
}

adds() {
    $NICE "${GIT_BINARY}" ls-files --others --exclude-standard | wc -l
}

deletes() {
    $NICE "${GIT_BINARY}" ls-files --deleted --exclude-standard | wc -l
}

git_poll () {
    local previous_path=$(pwd) 
    # Users might be using triggers to "Report Directory", which could pick up
    # a path with a '~' (representing the user's home) in it. Or it might be an
    # actual tilde in a directory name.
    local directory="${1/#\~/${HOME}}"
    cd "${directory}"

    ulimit -m 4096
    ulimit -t 2

    local xcode=$(xcode)
    local branch=$(branch)
    local dirty=$(dirty) 
    local push_count pull_count
    read push_count pull_count <<< "$(counts)"
    local adds=$(adds)
    local deletes=$(deletes)

    cd "${previous_path}"

    echo "--BEGIN--"
    echo "XCODE: ${xcode}"
    echo "DIRECTORY: ${directory}"
    echo "DIRTY: ${dirty}"
    echo "PUSH: ${push_count}"
    echo "PULL: ${pull_count}"
    echo "BRANCH: ${branch}"
    echo "ADDS: ${adds}"
    echo "DELETES: ${deletes}"
    echo "--END--"
    echo ""
}


while read line; do
    git_poll "$line"
done
