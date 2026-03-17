#!/bin/bash
# Updates the development team ID in all Xcode project files.
# Usage: tools/set_team_id.sh YOUR_TEAM_ID
#
# To find your team ID:
#   1. Open Keychain Access
#   2. Find your "Apple Development" or "Developer ID" certificate
#   3. The team ID is the string in parentheses, e.g., "H7V7XYVQ7D"

set -e

if [ -z "$1" ]; then
    echo "Usage: $0 TEAM_ID"
    echo ""
    echo "Updates DEVELOPMENT_TEAM in all Xcode project files."
    echo "To find your team ID, check your Apple Developer certificate in Keychain Access."
    exit 1
fi

TEAM_ID="$1"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

# All project files that have DEVELOPMENT_TEAM set
PROJECT_FILES=(
    "iTerm2.xcodeproj/project.pbxproj"
    "BetterFontPicker/BetterFontPicker.xcodeproj/project.pbxproj"
    "SearchableComboListView/SearchableComboListView.xcodeproj/project.pbxproj"
    "SignedArchive/SignedArchive.xcodeproj/project.pbxproj"
    "SignPlugin/SignPlugin.xcodeproj/project.pbxproj"
    "iTermAI/iTermAI.xcodeproj/project.pbxproj"
    "iTermBrowserPlugin/iTermBrowserPlugin.xcodeproj/project.pbxproj"
    "submodules/MultiCursor/MultiCursor.xcodeproj/project.pbxproj"
    "submodules/Highlightr/Highlightr.xcodeproj/project.pbxproj"
    "submodules/SwiftyMarkdown/SwiftyMarkdown.xcodeproj/project.pbxproj"
    "submodules/Sparkle/Sparkle.xcodeproj/project.pbxproj"
)

cd "$REPO_ROOT"

for proj in "${PROJECT_FILES[@]}"; do
    if [ -f "$proj" ]; then
        # Update DEVELOPMENT_TEAM = XXX;
        sed -i '' "s/DEVELOPMENT_TEAM = [^;]*;/DEVELOPMENT_TEAM = $TEAM_ID;/g" "$proj"

        # Update DevelopmentTeam = XXX; (camelCase variant in TargetAttributes)
        sed -i '' "s/DevelopmentTeam = [^;]*;/DevelopmentTeam = $TEAM_ID;/g" "$proj"

        # Update "DEVELOPMENT_TEAM[sdk=macosx*]" = XXX; (conditional)
        sed -i '' "s/\"DEVELOPMENT_TEAM\[sdk=macosx\*\]\" = [^;]*;/\"DEVELOPMENT_TEAM[sdk=macosx*]\" = $TEAM_ID;/g" "$proj"

        echo "Updated: $proj"
    else
        echo "Skipped (not found): $proj"
    fi
done

echo ""
echo "Done. Team ID set to: $TEAM_ID"
