#!/bin/zsh
# Called by run_tests.expect when a test run produces no output for too long.
# Saves what each test host was doing to the file named by $1 and prints a
# summary. Stack samples need no special permission for your own processes.
#
# A process state containing T means the process is stopped (by a debugger or a
# signal), not just slow.

report=$1
mkdir -p "$(dirname "$report")"

hosts=($(pgrep -f "iTerm2.app/Contents/MacOS/iTerm2 -suite iterm2-tests"))

{
    echo "Test stall report $(date)"
    echo
    echo "== Processes (STAT T = stopped)"
    ps -axo pid,ppid,stat,%cpu,rss,etime,command \
        | grep -E "iTerm2.app/Contents/MacOS/iTerm2 -suite iterm2-tests|xcodebuild test|debugserver|lldb|testmanagerd" \
        | grep -v grep | cut -c1-220
    for pid in $hosts; do
        echo
        echo "== Test host $pid"
        sample $pid 1 -mayDie 2>/dev/null
    done
} > "$report" 2>&1

echo
echo "*** Test hosts at the time of the stall (full stacks in $report):"
for pid in $hosts; do
    state=$(ps -o stat= -p $pid 2>/dev/null | tr -d ' ')
    # The innermost test frame on the main thread names the test that is stuck.
    test=$(awk -v pid="== Test host $pid" '
        $0 == pid { inhost = 1; next }
        inhost && /^== Test host/ { exit }
        inhost && /DispatchQueue_1: com.apple.main-thread/ { inmain = 1; next }
        inhost && inmain && /Thread_/ { exit }
        inhost && inmain && /ModernTests\)/ { line = $0 }
        END { print line }' "$report" \
        | sed -E 's/^[ +!:|]*[0-9]+ //; s/ \(in ModernTests\).*//' | cut -c1-140)
    echo "***   pid $pid state=${state:-gone} ${test:-(no test frame on the main thread)}"
done
