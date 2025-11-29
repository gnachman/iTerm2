# Adding Session Messages Customization to Xcode Project

## Files to Add to Xcode Project

The new Swift file needs to be added to the Xcode project:

### File to Add:
- `sources/PTYSession+SessionMessages.swift`

## Steps to Add to Xcode Project

### Method 1: Using Xcode GUI

1. Open `iTerm2.xcodeproj` in Xcode
2. In Project Navigator, right-click on the `sources` group
3. Select "Add Files to 'iTerm2'..."
4. Navigate to and select `sources/PTYSession+SessionMessages.swift`
5. **Important:** Make sure these options are checked:
   - ✅ Copy items if needed (if not already in sources)
   - ✅ Create groups
   - ✅ Add to targets: `iTerm2SharedARC`
6. Click "Add"

### Method 2: Using pbxproj Direct Edit (Advanced)

If you're comfortable editing the project file directly:

1. Open `iTerm2.xcodeproj/project.pbxproj` in a text editor
2. Find the section with other PTYSession files
3. Add a reference similar to existing Swift files
4. Save and reload project in Xcode

**Note:** This method is not recommended unless you're familiar with Xcode project structure.

## Connecting UI Elements in Interface Builder

After adding the Swift file, you need to connect the UI:

### Open XIB File:
1. In Xcode, navigate to `Interfaces/PreferencePanel.xib`
2. Open in Interface Builder

### Locate Terminal Preferences Tab:
1. Find the ProfilesWindow object
2. Navigate to the Terminal tab view
3. Look for the section with session end alerts (near _sessionEndedAlert checkbox)

### Add UI Elements:

#### 1. Session End Message Color
```
Position: Below existing session end alert checkbox
- Label (NSTextField): "Session End Message Color:"
- Color Well (NSColorWell): Connect outlet → _sessionEndMessageColorWell
```

#### 2. Session End Message Text
```
Position: Below color well
- Label (NSTextField): "Session Ended Text:"
- Text Field (NSTextField): Connect outlet → _sessionEndMessageText
  - Placeholder: "Session Ended"
```

#### 3. Session Restarted Message Text
```
Position: Below session ended text
- Label (NSTextField): "Session Restarted Text:"
- Text Field (NSTextField): Connect outlet → _sessionRestartedMessageText
  - Placeholder: "Session Restarted"
```

#### 4. Session Finished Message Text
```
Position: Below session restarted text
- Label (NSTextField): "Session Finished Text:"
- Text Field (NSTextField): Connect outlet → _sessionFinishedMessageText
  - Placeholder: "Finished"
```

### Connect Outlets:

1. Select the `ProfilesTerminalPreferencesViewController` object in Interface Builder
2. Open Connections Inspector (⌥⌘6)
3. Find the new outlets:
   - `_sessionEndMessageColorWell`
   - `_sessionEndMessageText`
   - `_sessionRestartedMessageText`
   - `_sessionFinishedMessageText`
4. Drag from each outlet to the corresponding UI element

### Layout Tips:

- Use Auto Layout constraints to maintain spacing
- Align labels to match existing UI style
- Use standard spacing (8-10pt between elements)
- Consider adding a separator or group box for visual organization

## Build Settings

The Swift file should automatically be included in the build if added correctly to `iTerm2SharedARC` target.

### Verify Build Target:
1. Select `sources/PTYSession+SessionMessages.swift` in Project Navigator
2. Open File Inspector (⌥⌘1)
3. Check "Target Membership" section
4. Ensure `iTerm2SharedARC` is checked

## Building and Testing

### Build the Project:
```bash
# From terminal
xcodebuild -project iTerm2.xcodeproj -scheme iTerm2 -configuration Debug
```

### Or in Xcode:
1. Select iTerm2 scheme
2. Product → Build (⌘B)
3. Fix any compilation errors

### Test the Feature:
1. Run iTerm2 (⌘R)
2. Open Preferences → Profiles → Terminal
3. Look for new session message customization controls
4. Modify color and text
5. Create a new terminal session
6. Type `exit` and verify custom message appears

## Troubleshooting

### If Swift file doesn't compile:
- Ensure it's in the correct target (`iTerm2SharedARC`)
- Check bridging header includes necessary Objective-C headers
- Verify Swift version compatibility in build settings

### If outlets don't connect:
- Verify `ProfilesTerminalPreferencesViewController.m` has the IBOutlet declarations
- Clean build folder (Shift+⌘K) and rebuild
- Check XIB file isn't corrupted

### If preferences don't save:
- Verify keys are defined in `ITAddressBookMgr.h`
- Check default values in `iTermProfilePreferences.m`
- Ensure `defineControl` calls are correct in `awakeFromNib`

## Alternative: Without XIB Modification

If you prefer not to modify the XIB, users can still set these preferences programmatically:

### Using defaults command:
```bash
# Get current profile GUID
profile_guid="YOUR-PROFILE-GUID"

# Set red color
defaults write com.googlecode.iterm2 "New Bookmarks" -dict-add "$profile_guid" \
  -dict-add "Session End Message Color" \
  -dict "Red Component" 1.0 "Green Component" 0.0 "Blue Component" 0.0 "Alpha Component" 1.0

# Set custom text
defaults write com.googlecode.iterm2 "New Bookmarks" -dict-add "$profile_guid" \
  -dict-add "Session End Message Text" "Connection Lost"
```

### Using Python API:
```python
import iterm2

async def main(connection):
    app = await iterm2.async_get_app(connection)
    profile = await app.async_get_profile_by_name("Default")
    
    # Set custom messages
    await profile.async_set_property("Session End Message Text", "🔴 Disconnected")
    await profile.async_set_property("Session Restarted Message Text", "🔄 Reconnected")
    await profile.async_set_property("Session Finished Message Text", "✅ Complete")

iterm2.run_until_complete(main)
```

## Documentation Files

These files provide additional information:
- `SESSION_MESSAGES_CUSTOMIZATION.md` - Feature documentation
- `IMPLEMENTATION_SUMMARY.md` - Technical implementation details
- `SESSION_MESSAGES_EXAMPLE.plist` - Example configuration
- `test_session_messages.m` - Example code snippets

## Summary Checklist

- [ ] Add `PTYSession+SessionMessages.swift` to Xcode project
- [ ] Add to `iTerm2SharedARC` target
- [ ] Open `PreferencePanel.xib` in Interface Builder
- [ ] Add 4 UI elements (1 color well, 3 text fields) with labels
- [ ] Connect outlets to `ProfilesTerminalPreferencesViewController`
- [ ] Build project (⌘B)
- [ ] Test in running app (⌘R)
- [ ] Verify preferences save and load correctly
- [ ] Test with different profiles
- [ ] Test emoji support 🎨

**Once complete, users can fully customize their session end messages!** 🎉
