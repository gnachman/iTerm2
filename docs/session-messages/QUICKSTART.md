# Quick Start - Session Messages Customization

## What Was Changed?

✅ **4 files modified** to enable user customization  
✅ **4 new preference keys** added  
✅ **100% backward compatible** - defaults match original behavior  
✅ **Ready to build and test**

## 5-Minute Setup

### Step 1: Add the Swift File to Xcode (Required)
```bash
# Open the project
open iTerm2.xcodeproj

# In Xcode:
# 1. Right-click 'sources' folder in Project Navigator
# 2. Choose 'Add Files to "iTerm2"...'
# 3. Select: sources/PTYSession+SessionMessages.swift
# 4. Check: Add to target 'iTerm2SharedARC'
# 5. Click 'Add'
```

### Step 2: Build the Project
```bash
# Command line (optional)
xcodebuild -project iTerm2.xcodeproj -scheme iTerm2 -configuration Debug

# Or in Xcode: Product → Build (⌘B)
```

### Step 3: Test It!

#### Option A: Use Advanced Settings Panel (EASIEST - No XIB needed!)
1. Run iTerm2
2. Open **Preferences → Advanced**
3. Search for "session" in the filter box
4. Find these settings under "Session:":
   - **Text displayed when a session ends**
   - **Text displayed when a session restarts**  
   - **Text displayed when a short-lived session finishes**
   - **Divider line style** (choose: none, single, double, dashed, dotted, heavy, light)
5. Type your custom text (emoji supported!)
6. Select your preferred line style!
7. Changes apply immediately - no restart needed!

#### Option B: Use defaults command
```bash
# Set custom messages
defaults write com.googlecode.iterm2 sessionEndMessageText "🔴 Connection Lost"
defaults write com.googlecode.iterm2 sessionRestartedMessageText "🔄 Reconnected"
defaults write com.googlecode.iterm2 sessionFinishedMessageText "✅ Done"

# Choose divider style (7 options!)
defaults write com.googlecode.iterm2 sessionEndMessageDividerStyle "none"    # No lines
defaults write com.googlecode.iterm2 sessionEndMessageDividerStyle "single"  # Thin ─
defaults write com.googlecode.iterm2 sessionEndMessageDividerStyle "double"  # Bold ━
defaults write com.googlecode.iterm2 sessionEndMessageDividerStyle "dashed"  # Dash ╌
defaults write com.googlecode.iterm2 sessionEndMessageDividerStyle "dotted"  # Dots ┄
defaults write com.googlecode.iterm2 sessionEndMessageDividerStyle "heavy"   # Heavy ═
defaults write com.googlecode.iterm2 sessionEndMessageDividerStyle "light"   # Light ─

# Restart iTerm2 to see changes
```

#### Option C: Use Objective-C API
```objc
// In your code
[iTermAdvancedSettingsModel setSessionEndMessageText:@"🔴 Disconnected"];
[iTermAdvancedSettingsModel setSessionRestartedMessageText:@"🔄 Reconnected"];
[iTermAdvancedSettingsModel setSessionFinishedMessageText:@"✅ Complete"];
```

### Step 4: See Your Custom Messages

Open a new terminal and type:
```bash
exit
```

You should see your custom colored message! 🎉

## Quick Examples

### Example 1: Red Warning Style
```python
Color: RGB(255, 0, 0)
Text: "⚠️ SESSION TERMINATED"
```

### Example 2: Green Success Style
```python
Color: RGB(0, 200, 0)
Text: "✅ Task Complete"
```

### Example 3: Professional Style
```python
Color: RGB(100, 100, 100)
Text: "Connection closed by remote host"
```

## Troubleshooting

### "Swift file not compiling"
- Make sure it's added to `iTerm2SharedARC` target
- Clean build folder: Shift+⌘K then ⌘B

### "Can't find preference keys"
- Check `ITAddressBookMgr.h` has the new #define statements
- Rebuild the project

### "Preferences not saving"
- Quit iTerm2 completely
- Run `defaults read com.googlecode.iterm2 | grep "Session End Message"`
- Should see your custom values

### "Messages not appearing"
- Check you're using the modified profile
- Try creating a new session
- Verify defaults are set correctly

## Files Reference

| File | Purpose |
|------|---------|
| `SESSION_MESSAGES_CUSTOMIZATION.md` | 📖 Complete documentation |
| `IMPLEMENTATION_SUMMARY.md` | 🛠️ Technical details |
| `XCODE_PROJECT_SETUP.md` | ⚙️ Xcode setup guide |
| `VISUAL_EXAMPLES.md` | 🎨 Visual examples & ideas |
| `SESSION_MESSAGES_EXAMPLE.plist` | 📄 Example config |
| `test_session_messages.m` | 💻 Code examples |
| `QUICKSTART.md` | 🚀 This file |

## Next Steps

1. ✅ Build and test basic functionality
2. ⚙️ [Optional] Add UI in XIB (see XCODE_PROJECT_SETUP.md)
3. 🎨 Experiment with colors and text
4. 🚀 Create custom profiles for different environments
5. 📱 Share your configurations with your team

## Cool Ideas to Try

```bash
# Production server - Red alerts (with dividers for emphasis)
"⚠️ PROD SESSION ENDED"

# Dev environment - Green friendly
"💚 Dev Session Closed"

# Docker containers - Blue tech
"🐳 Container Exited"

# SSH sessions - Yellow caution
"🔐 SSH Disconnected"

# Clean minimal (NO dividers)
"Session closed" + disable dividers

# Ultra minimal (NO dividers)
"─" + disable dividers

# Emoji only (NO dividers)
"🔴" + disable dividers

# Professional (NO dividers)
"Connection closed by remote host" + disable dividers

# Fun emoji style
"🎭 Show's Over!"
```

**To disable divider lines:**
```bash
defaults write com.googlecode.iterm2 showSessionEndMessageDividers -bool false
```

## Pro Tips

💡 **Use consistent colors** across related profiles  
💡 **Keep messages short** (under 30 chars)  
💡 **Test with both light and dark themes**  
💡 **Emoji look great** but don't overdo it  
💡 **Create a naming convention** for your team  

## Support

For issues or questions:
1. Check the documentation files
2. Review `PTYSession.m` changes
3. Verify preference keys are defined
4. Test with default profile first

## That's It!

You now have fully customizable session end messages. Enjoy personalizing your terminal experience! 🎉

```
┌────────────────────────────────────────────┐
│                                            │
│   ━━━━━━ 🎨 Happy Customizing! 🎨 ━━━━━━   │
│                                            │
└────────────────────────────────────────────┘
```
