# Session Message Divider Options

## The Problem

You don't like the blue divider lines around the session end message:

```
━━━━━━━━━━━━━━━━━━ Session Ended ━━━━━━━━━━━━━━━━━━
```

## The Solution

**New setting:** `showSessionEndMessageDividers`

Turn it OFF to remove those lines!

## Visual Comparison

### With Dividers (Default - YES)
```
--Truman Burbank
━━━━━━━━━━━━━━━━━━ Session Ended ━━━━━━━━━━━━━━━━━━


```

### Without Dividers (NO)
```
--Truman Burbank
 Session Ended 


```

### Without Dividers + Custom Text
```
--Truman Burbank
 Connection closed 


```

### Minimal Style (No dividers + short text)
```
--Truman Burbank
 ─ 


```

## How to Disable Dividers

### Option 1: Advanced Settings
1. Preferences → Advanced
2. Search: "divider"
3. Uncheck: **"Show decorative divider lines around session end messages"**

### Option 2: Terminal Command
```bash
# Disable dividers
defaults write com.googlecode.iterm2 showSessionEndMessageDividers -bool false

# Re-enable dividers
defaults write com.googlecode.iterm2 showSessionEndMessageDividers -bool true
```

### Option 3: Programmatically
```objc
[iTermAdvancedSettingsModel setShowSessionEndMessageDividers:NO];
```

## Different Styles You Can Achieve

### 1. Clean & Minimal
```bash
defaults write com.googlecode.iterm2 showSessionEndMessageDividers -bool false
defaults write com.googlecode.iterm2 sessionEndMessageText "Session closed"
```
Result:
```
 Session closed 
```

### 2. Emoji Only (No lines)
```bash
defaults write com.googlecode.iterm2 showSessionEndMessageDividers -bool false
defaults write com.googlecode.iterm2 sessionEndMessageText "🔴"
```
Result:
```
 🔴 
```

### 3. Professional (No lines)
```bash
defaults write com.googlecode.iterm2 showSessionEndMessageDividers -bool false
defaults write com.googlecode.iterm2 sessionEndMessageText "Connection closed by remote host"
```
Result:
```
 Connection closed by remote host 
```

### 4. Barely Visible
```bash
defaults write com.googlecode.iterm2 showSessionEndMessageDividers -bool false
defaults write com.googlecode.iterm2 sessionEndMessageText "·"
```
Result:
```
 · 
```

### 5. Traditional with Lines (Keep default)
```bash
defaults write com.googlecode.iterm2 showSessionEndMessageDividers -bool true
defaults write com.googlecode.iterm2 sessionEndMessageText "Session Ended"
```
Result:
```
━━━━━━━━━━━━━━━━━━ Session Ended ━━━━━━━━━━━━━━━━━━
```

## Design Philosophy

**With dividers:** Makes the message **stand out** - good for important alerts  
**Without dividers:** Keeps the terminal **clean** - good for minimal aesthetic

Choose based on your preference! The message will still be colored and visible either way.

## Testing

1. Disable dividers:
   ```bash
   defaults write com.googlecode.iterm2 showSessionEndMessageDividers -bool false
   ```

2. Restart iTerm2 or open new terminal

3. Type `exit`

4. See your clean message without those blue lines! ✨

## Summary

- **Setting:** `showSessionEndMessageDividers` (boolean)
- **Default:** YES (lines shown)
- **To disable:** Set to NO/false
- **Location:** Preferences → Advanced → Session section
- **Effect:** Removes blue divider lines, keeps colored text

Your terminal, your style! 🎨
