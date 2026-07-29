#!/bin/bash
# iTerm2 Window Projects & Cold Storage E2E Integration Test (PID isolated)
# Spawns iTerm2, starts a background command, freezes it, verifies process survival, and restores it.

set -o pipefail

APP_PATH="/Users/ysaxon/Library/Developer/Xcode/DerivedData/iTerm2-hghphmhudlrmuogydilxgbnitkjo/Build/Products/Development/iTerm2.app"
TEST_PROJECT="E2E-Test-Project"

echo "--------------------------------------------------------"
echo "🚀 STARTING COLD STORAGE E2E SYSTEM INTEGRATION TEST"
echo "--------------------------------------------------------"

# 1. Launch our specific development iTerm2 app
echo "1. Launching development iTerm2..."
open "$APP_PATH"
sleep 4

# Retrieve the specific PID of our development instance
DEV_PID=$(pgrep -f "$APP_PATH/Contents/MacOS/iTerm2" | head -n 1)
if [ -z "$DEV_PID" ]; then
    echo "❌ Error: Could not find the PID of the running development iTerm2!"
    exit 1
fi
echo "✅ Isolated development iTerm2 PID: $DEV_PID (Safely avoiding your production iTerm)"

# 2. Spawn a terminal window and run our unique loop targeting the dev path
echo "2. Launching a terminal window with a sleep task..."
osascript <<EOD
tell application "$APP_PATH"
    activate
    set newWindow to (create window with default profile)
    tell newWindow
        tell current session
            write text "/bin/sleep 1001"
        end tell
    end tell
end tell
EOD
sleep 3

# 3. Associate the window with our test project
echo "3. Associating window with project '$TEST_PROJECT'..."
osascript <<EOD
tell application "System Events"
    set frontmost of (first process whose unix id is $DEV_PID) to true
    delay 1 -- Wait for focus transition
    
    tell (first process whose unix id is $DEV_PID)
        -- Open the Window Projects panel
        click menu item "Window Projects…" of menu "Window" of menu bar 1
        delay 1
        
        -- Create a new project inside the splitter group
        click button "+" of splitter group 1 of window "Window Projects"
        delay 1
        keystroke "$TEST_PROJECT"
        keystroke return
        delay 1
        
        -- Associate our active window with the project
        click button "Associate with Project" of splitter group 1 of window "Window Projects"
        delay 1
    end tell
end tell
EOD

# Let's verify our sleep process is actively running on the system
PID=$(pgrep -f "sleep 1001" | head -n 1)
if [ -z "$PID" ]; then
    echo "❌ Error: Sleep process was not found running! Is 'Run Jobs in Servers' enabled?"
    exit 1
fi
echo "✅ Found live sleep process running on PID: $PID"

# 4. Freeze the window (Archive & Keep Jobs Running)
echo "4. Freezing terminal window to cold storage (Orphaning)..."
osascript <<EOD
tell application "System Events"
    set frontmost of (first process whose unix id is $DEV_PID) to true
    delay 1
    
    tell (first process whose unix id is $DEV_PID)
        -- Click the Freeze All button to close the window and orphan jobs
        click button "Freeze All" of splitter group 1 of window "Window Projects"
        delay 2
    end tell
end tell
EOD

# Wait for window teardown
sleep 2

# 5. ASSERTION: Process Survival
echo "5. Verifying process survival (Orphan Verification)..."
SURVIVED_PID=$(pgrep -f "sleep 1001" | head -n 1)
if [ -n "$SURVIVED_PID" ]; then
    echo "✅ SUCCESS: Background process group $SURVIVED_PID survived cold storage closure!"
else
    echo "❌ FAILURE: Background process was terminated upon window closure!"
    exit 1
fi

# 6. Thaw / Restore the window
echo "6. Thawing (restoring) the window from cold storage..."
osascript <<EOD
tell application "System Events"
    set frontmost of (first process whose unix id is $DEV_PID) to true
    delay 1
    
    tell (first process whose unix id is $DEV_PID)
        -- Open Window Projects panel again
        click menu item "Window Projects…" of menu "Window" of menu bar 1
        delay 1
        
        -- Click Restore All button
        click button "Restore All" of splitter group 1 of window "Window Projects"
        delay 2
        
        -- Close the panel to tidy up
        click button 1 of window "Window Projects"
    end tell
end tell
EOD

echo "--------------------------------------------------------"
echo "🎉 INTEGRATION VERIFICATION COMPLETE!"
echo "--------------------------------------------------------"
