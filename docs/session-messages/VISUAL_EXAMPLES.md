# Visual Examples - Session Messages Customization

## Before and After

### Before (Original Behavior)
```
Terminal Output:
───────────────────────────────────────────────────────────────
$ exit
━━━━━━━━━━━━━━━━━━ Session Ended ━━━━━━━━━━━━━━━━━━━
                   (Blue color)
```

### After (With Customization)
```
Terminal Output - Example 1 (Red warning style):
───────────────────────────────────────────────────────────────
$ exit
━━━━━━━━━━━━━━━ 🔴 Connection Closed ━━━━━━━━━━━━━━━
                   (Red color)
```

```
Terminal Output - Example 2 (Green success style):
───────────────────────────────────────────────────────────────
$ exit
━━━━━━━━━━━━━━━━━━ ✅ Finished ━━━━━━━━━━━━━━━━━━━━
                   (Green color)
```

```
Terminal Output - Example 3 (Purple custom style):
───────────────────────────────────────────────────────────────
$ exit
━━━━━━━━━━━━━━━━ Connection Terminated ━━━━━━━━━━━━━━━
                   (Purple color)
```

## UI Layout (Preferences Panel)

### Location: Preferences → Profiles → Terminal

```
┌─ Session ──────────────────────────────────────────────┐
│                                                         │
│ ☐ Automatically log session input to files in:         │
│ [ /Users/username/logs ▼ ]                             │
│                                                         │
│ ☐ Send bell alert                                      │
│ ☐ Send idle alert                                      │
│ ☐ Send new output alert                                │
│ ☑ Send session ended alert                             │
│ ☐ Send terminal generated alerts                       │
│                                                         │
│ ┌─ Session End Messages ──────────────────────┐       │
│ │                                               │       │
│ │ Session End Message Color:  [🎨 Blue     ]   │       │
│ │                                               │       │
│ │ Session Ended Text:                           │       │
│ │ [Session Ended                            ]   │       │
│ │                                               │       │
│ │ Session Restarted Text:                       │       │
│ │ [Session Restarted                        ]   │       │
│ │                                               │       │
│ │ Session Finished Text:                        │       │
│ │ [Finished                                 ]   │       │
│ │                                               │       │
│ └───────────────────────────────────────────────┘       │
│                                                         │
└─────────────────────────────────────────────────────────┘
```

## Color Examples

### Production Server Profile (Red)
```yaml
Color: RGB(255, 0, 0) - Bright Red
Messages:
  - Session Ended: "⚠️ PRODUCTION SESSION ENDED"
  - Session Restarted: "🔄 PRODUCTION RECONNECTED"
  - Finished: "✅ PRODUCTION TASK COMPLETE"
```

### Development Server Profile (Green)
```yaml
Color: RGB(0, 200, 0) - Green
Messages:
  - Session Ended: "💚 Dev Session Closed"
  - Session Restarted: "♻️ Dev Reconnected"
  - Finished: "✨ Dev Task Done"
```

### Remote SSH Profile (Blue)
```yaml
Color: RGB(0, 150, 255) - Sky Blue
Messages:
  - Session Ended: "🌐 SSH Disconnected"
  - Session Restarted: "🔐 SSH Reconnected"
  - Finished: "📡 SSH Transfer Complete"
```

### Docker Container Profile (Purple)
```yaml
Color: RGB(150, 0, 200) - Purple
Messages:
  - Session Ended: "🐳 Container Exited"
  - Session Restarted: "🔄 Container Restarted"
  - Finished: "📦 Container Task Complete"
```

## Terminal Display Details

### Message Structure
```
[Divider Image] [Padded Message Text] [Divider Image]
     ━━━━━━━━        Session Ended       ━━━━━━━━
```

### Color Application
- Text color: Uses custom profile color
- Background: Default terminal background
- Divider images: BrokenPipeDivider.png (colored to match text)

## Notification Examples

When "Send session ended alert" is enabled:

### Before
```
macOS Notification:
┌────────────────────────────────────┐
│ iTerm2                             │
│ Session Ended                      │
│ Session "bash" in tab #1 just      │
│ terminated.                        │
└────────────────────────────────────┘
```

### After (With Custom Text)
```
macOS Notification:
┌────────────────────────────────────┐
│ iTerm2                             │
│ 🔴 Connection Closed               │
│ Session "bash" in tab #1 just      │
│ terminated.                        │
└────────────────────────────────────┘
```

## Real-World Use Cases

### 1. Team Color Coding
Different teams use different colors:
- Frontend: Blue messages
- Backend: Green messages  
- DevOps: Orange messages
- Database: Purple messages

### 2. Environment Indicators
- Production: Red with WARNING prefix
- Staging: Yellow/Orange
- Development: Green with SAFE indicator
- Local: Blue default

### 3. Multi-Language Support
```
English:  "Session Ended"
Spanish:  "Sesión Terminada"
French:   "Session Terminée"
German:   "Sitzung Beendet"
Japanese: "セッション終了"
Chinese:  "会话已结束"
Emoji:    "🔴 ❌ 🛑"
```

### 4. Project-Specific Messages
```
Web Dev:      "🌐 Server Stopped"
Data Science: "📊 Analysis Complete"
Gaming:       "🎮 Game Server Offline"
ML Training:  "🤖 Training Session Ended"
CI/CD:        "⚙️ Pipeline Stopped"
```

## Comparison Chart

| Aspect              | Before            | After                    |
|---------------------|-------------------|--------------------------|
| **Color**           | Fixed Blue        | Any RGB color            |
| **Text**            | Fixed English     | Any text, any language   |
| **Emoji**           | Not supported     | ✅ Full emoji support    |
| **Per-Profile**     | Global only       | ✅ Per-profile settings  |
| **Customization**   | Code change only  | ✅ UI + Programmatic     |
| **Backward Compat** | N/A               | ✅ 100% compatible       |

## Advanced Styling Ideas

### Minimalist
```
Text: "─"
Color: Subtle gray
Result: Almost invisible separator
```

### Bold and Clear
```
Text: "⚠️ ═══ CONNECTION LOST ═══ ⚠️"
Color: Bright red
Result: Very noticeable alert
```

### Status Icons
```
Ended:    "● Session Closed"
Restart:  "○ Session Active"
Finished: "◆ Task Complete"
```

### Time-based (with scripting)
```python
# Auto-set message based on time of day
if hour < 12:
    message = "☀️ Morning Session Ended"
elif hour < 17:
    message = "🌤️ Afternoon Session Ended"
else:
    message = "🌙 Evening Session Ended"
```

## Preview in Different Themes

### Light Theme
```
Session Ended message with dark text color looks best
Recommended: Dark blue, dark red, black
```

### Dark Theme
```
Session Ended message with bright text color looks best
Recommended: Bright blue, bright red, cyan, yellow
```

### Solarized Dark
```
Session Ended message with Solarized accent colors
Recommended: Solarized blue, cyan, green
```

## Tips for Best Results

1. **Contrast**: Ensure good contrast with terminal background
2. **Length**: Keep messages concise (under 40 characters)
3. **Emoji**: Use sparingly for better readability
4. **Testing**: Test with both light and dark themes
5. **Consistency**: Use consistent style across related profiles

## Inspiration Gallery

```
Retro:     ">>> SESSION TERMINATED <<<"
Modern:    "⟫ Connection Lost ⟪"
Fun:       "🎉 Party's Over! 🎊"
Serious:   "⚠️ CRITICAL: Session Ended"
Gaming:    "💀 You Died"
Developer: "🐛 Debug Session Closed"
Ops:       "🚨 Service Disconnected"
Minimal:   "·"
Verbose:   "The remote connection has been terminated"
```

Remember: The message appears in the terminal buffer and stays visible in scrollback, so choose something you'll want to see in your session history!
