# Session Message Divider Styles

Choose from **7 different divider line styles** for your session end messages!

## Available Styles

### 1. None (Clean)
**Value:** `none`

```
 Session Ended 
```

No divider lines at all - just the message text. Ultra clean!

---

### 2. Single Line (Minimal)
**Value:** `single`

```
──────────────────── Session Ended ────────────────────
```

Thin, single-weight horizontal line. Subtle and elegant.

---

### 3. Double Line (Default)
**Value:** `double`

```
━━━━━━━━━━━━━━━━━━ Session Ended ━━━━━━━━━━━━━━━━━━
```

Thick, bold horizontal line. This is the current default - stands out clearly.

---

### 4. Dashed Line (Casual)
**Value:** `dashed`

```
╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌ Session Ended ╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌
```

Dashed horizontal line. Softer look than solid lines.

---

### 5. Dotted Line (Subtle)
**Value:** `dotted`

```
┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄ Session Ended ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄
```

Dotted horizontal line. Very subtle, almost invisible.

---

### 6. Heavy Line (Emphatic)
**Value:** `heavy`

```
══════════════════ Session Ended ══════════════════
```

Extra heavy double line. Maximum visual impact!

---

### 7. Light Line (Delicate)
**Value:** `light`

```
──────────────────── Session Ended ────────────────────
```

Light weight line. Same as single but explicitly named.

---

## How to Set Your Style

### Via Advanced Settings (Easiest)
1. Preferences → Advanced
2. Search: "divider"
3. Find: **"Divider line style for session end messages"**
4. Type one of: `none`, `single`, `double`, `dashed`, `dotted`, `heavy`, `light`

### Via Terminal
```bash
# No lines (clean)
defaults write com.googlecode.iterm2 sessionEndMessageDividerStyle "none"

# Single line (minimal)
defaults write com.googlecode.iterm2 sessionEndMessageDividerStyle "single"

# Double line (default)
defaults write com.googlecode.iterm2 sessionEndMessageDividerStyle "double"

# Dashed line (casual)
defaults write com.googlecode.iterm2 sessionEndMessageDividerStyle "dashed"

# Dotted line (subtle)
defaults write com.googlecode.iterm2 sessionEndMessageDividerStyle "dotted"

# Heavy line (emphatic)
defaults write com.googlecode.iterm2 sessionEndMessageDividerStyle "heavy"

# Light line (delicate)
defaults write com.googlecode.iterm2 sessionEndMessageDividerStyle "light"
```

### Via Code
```objc
[iTermAdvancedSettingsModel setSessionEndMessageDividerStyle:@"single"];
```

---

## Visual Comparison

```
╔═══════════════════════════════════════════════════════════╗
║ NONE                                                      ║
║  Session Ended                                            ║
╠═══════════════════════════════════════════════════════════╣
║ SINGLE                                                    ║
║ ──────────────────── Session Ended ──────────────────────║
╠═══════════════════════════════════════════════════════════╣
║ DOUBLE (Default)                                          ║
║ ━━━━━━━━━━━━━━━━━━ Session Ended ━━━━━━━━━━━━━━━━━━      ║
╠═══════════════════════════════════════════════════════════╣
║ DASHED                                                    ║
║ ╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌ Session Ended ╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌    ║
╠═══════════════════════════════════════════════════════════╣
║ DOTTED                                                    ║
║ ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄ Session Ended ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄    ║
╠═══════════════════════════════════════════════════════════╣
║ HEAVY                                                     ║
║ ══════════════════ Session Ended ══════════════════      ║
╠═══════════════════════════════════════════════════════════╣
║ LIGHT                                                     ║
║ ──────────────────── Session Ended ──────────────────────║
╚═══════════════════════════════════════════════════════════╝
```

---

## Recommendations by Use Case

### Clean & Minimal
```bash
defaults write com.googlecode.iterm2 sessionEndMessageDividerStyle "none"
defaults write com.googlecode.iterm2 sessionEndMessageText "Connection closed"
```

### Professional
```bash
defaults write com.googlecode.iterm2 sessionEndMessageDividerStyle "single"
defaults write com.googlecode.iterm2 sessionEndMessageText "Session terminated"
```

### Traditional (Keep default)
```bash
defaults write com.googlecode.iterm2 sessionEndMessageDividerStyle "double"
defaults write com.googlecode.iterm2 sessionEndMessageText "Session Ended"
```

### Attention-Grabbing (Production servers)
```bash
defaults write com.googlecode.iterm2 sessionEndMessageDividerStyle "heavy"
defaults write com.googlecode.iterm2 sessionEndMessageText "⚠️ PRODUCTION SESSION ENDED"
```

### Subtle & Quiet
```bash
defaults write com.googlecode.iterm2 sessionEndMessageDividerStyle "dotted"
defaults write com.googlecode.iterm2 sessionEndMessageText "·"
```

---

## Unicode Characters Used

| Style  | Character | Unicode | Name |
|--------|-----------|---------|------|
| Single | ─        | U+2500  | Box Drawings Light Horizontal |
| Double | ━        | U+2501  | Box Drawings Heavy Horizontal |
| Dashed | ╌        | U+254C  | Box Drawings Light Double Dash Horizontal |
| Dotted | ┄        | U+2504  | Box Drawings Light Triple Dash Horizontal |
| Heavy  | ═        | U+2550  | Box Drawings Double Horizontal |
| Light  | ─        | U+2500  | Box Drawings Light Horizontal |

All characters are standard Unicode box-drawing characters that render properly in most fonts!

---

## Mixing Styles with Custom Text

### Emoji + No lines
```bash
defaults write com.googlecode.iterm2 sessionEndMessageDividerStyle "none"
defaults write com.googlecode.iterm2 sessionEndMessageText "🔴"
```

### Custom text + Single line
```bash
defaults write com.googlecode.iterm2 sessionEndMessageDividerStyle "single"
defaults write com.googlecode.iterm2 sessionEndMessageText "Connection closed"
```

### Heavy emphasis
```bash
defaults write com.googlecode.iterm2 sessionEndMessageDividerStyle "heavy"
defaults write com.googlecode.iterm2 sessionEndMessageText "⚠️ SERVER DISCONNECTED"
```

### Minimal separator
```bash
defaults write com.googlecode.iterm2 sessionEndMessageDividerStyle "dotted"
defaults write com.googlecode.iterm2 sessionEndMessageText "─"
```

---

## Testing Different Styles

Try them all!

```bash
# Test each style
for style in none single double dashed dotted heavy light; do
  defaults write com.googlecode.iterm2 sessionEndMessageDividerStyle "$style"
  echo "Set to: $style - restart iTerm2 and type 'exit' to see it"
  read -p "Press enter to try next style..."
done
```

---

## What About Colors?

The divider lines use the **same color** as the message text (blue by default). The color is customizable via the profile's message color setting.

The **style** (none/single/double/etc) only controls the **character** used, not the color.

---

## Summary

- **7 styles available**: none, single, double, dashed, dotted, heavy, light
- **Default**: double (current behavior)
- **Setting**: `sessionEndMessageDividerStyle` (string)
- **Location**: Advanced Settings → Session
- **Unicode safe**: All styles use standard box-drawing characters
- **Color**: Inherits from message color setting

Choose the style that matches your aesthetic! 🎨
