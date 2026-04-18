# Korean IME Enter Key Issue — Analysis & Solutions

## Problem Summary

When typing Korean (Hangul) in iTerm2 and pressing Enter, the input is sometimes not sent immediately. Users need to press Enter **twice**: once to confirm the IME composition, once to send the command.

## Root Cause Analysis

### 1. How IME Composition Works

macOS IME (Input Method Editor) for Korean uses a **composition model**:

```
User types: ㅎ → 하 → 한 → 한g → 한국
                         ↑ composition in progress
Press Enter → confirms "한국" (first Enter)
Press Enter → sends newline to terminal (second Enter)
```

This is **expected IME behavior** — not an iTerm2 bug per se. However, it creates friction.

### 2. NSTextView Composition State

The standard macOS text input pipeline:
1. `keyDown:` receives raw key event
2. `interpretKeyEvents:` routes to IME
3. IME may **consume** Enter to confirm composition
4. Only after confirmation does Enter propagate as `\n`

### 3. iTerm2 Specific Layer

`PTYTextView` overrides `keyDown:` for terminal input. The interaction:

```
keyDown: (Enter pressed)
  └─ interpretKeyEvents: 
       ├─ [IME in composition] → confirms composition, Enter consumed
       └─ [IME idle] → insertNewline: → sends \n to PTY
```

### 4. Reproduction Conditions

| Condition | Reproduces? |
|---|---|
| Korean IME + bash + Enter | ✅ Yes |
| English input + Enter | ❌ No |
| Korean IME + tmux + Enter | ✅ Yes (same) |
| Korean IME + Claude Code TUI | ✅ Yes (especially problematic) |
| Korean IME + Codex TUI | ✅ Yes |
| Korean IME after switching to English | ❌ No |

## Workarounds (Immediate)

### Option 1: Switch to English before pressing Enter
- Switch IME: `Caps Lock` or `⌘Space`
- Press Enter
- Switch back

### Option 2: Use Ctrl+J instead of Enter
- `Ctrl+J` sends the same `\n` character
- Bypasses IME composition confirmation
- Works in most shells

### Option 3: Configure Squash IME behavior
In System Settings > Keyboard > Input Sources:
- Check if "Use the Caps Lock key to switch languages" helps

### Option 4: iTerm2 Profile setting
Preferences > Profiles > Keys:
- Try enabling "xterm defaults" key mapping
- Check if any existing Enter key remapping exists

## Proper Fix Approaches

### Fix A: Intercept Enter in Composition State (PTYTextView)

In `PTYTextView.m`, in `keyDown:`:
```objc
// If IME is composing and Enter is pressed, finalize composition first
if ([self hasMarkedText] && keyCode == kVK_Return) {
    [self unmarkText];
    // Don't consume — let Enter propagate normally
}
```

### Fix B: Force-commit composition on specific keys

Override `doCommandBySelector:` in PTYTextView:
```objc
- (void)doCommandBySelector:(SEL)aSelector {
    if (aSelector == @selector(insertNewline:) && [self hasMarkedText]) {
        // Commit composition
        [self insertText:[[self markedTextRange] string] 
        replacementRange:NSMakeRange(NSNotFound, 0)];
        // Then send newline
    }
    [super doCommandBySelector:aSelector];
}
```

### Fix C: Keyboard shortcut workaround via trigger
Create an iTerm2 trigger that maps a specific key to send `\n` immediately.

## Recommended Action

1. **Short-term**: Document Option 2 (Ctrl+J) in the onboarding guide
2. **Medium-term**: Implement Fix A in `PTYTextView.m`
3. **Test**: Verify with different Korean input methods (2-beol, 3-beol)
4. **Validate**: Test in tmux, Claude Code TUI, and Codex TUI environments

## Files to Modify

- `sources/PTYTextView.m` — main keyboard input handler
- Look for `keyDown:` method (~line 3000-4000 range)
- Search for `hasMarkedText` to find existing IME handling

## Reference Issues

- iTerm2 GitHub: search "Korean IME Enter"
- macOS IME documentation: `NSTextInputClient` protocol
- Key event: `kVK_Return` = 0x24, `kVK_ANSI_KeypadEnter` = 0x4C
