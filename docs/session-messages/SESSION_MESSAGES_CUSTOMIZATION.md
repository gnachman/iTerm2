# Session Messages Customization

This feature allows users to customize the **color** and **text** of session end messages in iTerm2.

## What This Feature Does

When a terminal session ends, restarts, or finishes, iTerm2 displays a message in the terminal. Previously, these messages had hard-coded text and color:
- "Session Ended" in blue
- "Session Restarted" in blue  
- "Finished" in blue

Now users can customize both the **color** and the **text** of these messages per profile.

## Added Preference Keys

The following new preference keys have been added to `ITAddressBookMgr.h`:

- `KEY_SESSION_END_MESSAGE_COLOR` - Color for session end messages
- `KEY_SESSION_END_MESSAGE_TEXT` - Text for "Session Ended" message
- `KEY_SESSION_RESTARTED_MESSAGE_TEXT` - Text for "Session Restarted" message  
- `KEY_SESSION_FINISHED_MESSAGE_TEXT` - Text for "Finished" message

## Default Values

Default values are set in `iTermProfilePreferences.m`:

- **Color**: RGB(70/255, 83/255, 246/255) - blue color (matches original)
- **Session Ended**: "Session Ended"
- **Session Restarted**: "Session Restarted"
- **Finished**: "Finished"

## Implementation

### Modified Files:

1. **ITAddressBookMgr.h** - Added new key definitions
2. **iTermProfilePreferences.m** - Added default values for new keys
3. **PTYSession.m** - Updated to read custom color and text from profile preferences:
   - `appendBrokenPipeMessage:` - Now uses `KEY_SESSION_END_MESSAGE_COLOR`
   - `brokenPipeWithError:` - Uses `KEY_SESSION_END_MESSAGE_TEXT` for notifications
   - Session restart logic - Uses `KEY_SESSION_RESTARTED_MESSAGE_TEXT`
   - Short-lived session logic - Uses `KEY_SESSION_FINISHED_MESSAGE_TEXT`

4. **ProfilesTerminalPreferencesViewController.m** - Added outlets and control definitions for UI:
   - `_sessionEndMessageColorWell` - Color picker
   - `_sessionEndMessageText` - Text field for "Session Ended"
   - `_sessionRestartedMessageText` - Text field for "Session Restarted"
   - `_sessionFinishedMessageText` - Text field for "Finished"

## How to Use

### Via Advanced Settings Panel (Easiest):

1. Build and run iTerm2
2. Open **Preferences → Advanced**
3. Search for "session" or scroll to the "Session:" section
4. Find and modify these settings:
   - **Session: Text displayed when a session ends**
   - **Session: Text displayed when a session restarts**
   - **Session: Text displayed when a short-lived session finishes**
5. Type your custom text (emoji supported! 🎉)
6. Changes apply immediately

### Programmatically:

```objc
// Set custom text via Advanced Settings
[iTermAdvancedSettingsModel setSessionEndMessageText:@"🔴 Connection Lost"];
[iTermAdvancedSettingsModel setSessionRestartedMessageText:@"🔄 Reconnected"];
[iTermAdvancedSettingsModel setSessionFinishedMessageText:@"✅ Complete"];
```

### Via defaults command:

```bash
# Set custom text
defaults write com.googlecode.iterm2 sessionEndMessageText "🔴 Disconnected"
defaults write com.googlecode.iterm2 sessionRestartedMessageText "🔄 Reconnected"
defaults write com.googlecode.iterm2 sessionFinishedMessageText "✅ Done"

# Restart iTerm2 to see changes
```

## Testing

After building with these changes:

1. Open iTerm2 Preferences → Profiles → Terminal
2. Modify the session end message color and texts
3. Start a new session with that profile
4. Exit the session (type `exit`)
5. Verify your custom color and text appear in the session end message

## Future Enhancements

Potential additions:
- Support for bold/italic text styling
- Font customization for messages
- Support for emoji in message text
- Different colors for different message types (ended vs restarted vs finished)
