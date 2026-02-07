# WebKit Media Playback Entitlements

## Background

The transparent browser feature requires WebKit to handle media playback. However, certain system-level entitlements are restricted and cannot be used in regular development builds.

## Restricted Entitlements

The following entitlements are **system-level privileges** that require special approval from Apple:

- `com.apple.runningboard.assertions.webkit` - WebKit process assertion control
- `com.apple.multitasking.systemappassertions` - System-wide multitasking assertions

## Impact on Development Builds

### What Works
✅ Basic web browsing with transparency
✅ Static content rendering
✅ JavaScript execution
✅ User interaction
✅ Transparency slider control

### Known Limitations
⚠️ **Media playback warnings**: You'll see console warnings like:
```
ProcessAssertion::acquireSync Failed to acquire RBS assertion 'WebKit Media Playback'
```

These warnings are **cosmetic** and don't prevent media playback. WebKit falls back to a restricted mode that still allows:
- Video/audio playback (with some restrictions)
- Basic media controls
- Streaming content

### What Doesn't Work Without Entitlements
❌ Background media playback (when app is hidden)
❌ System-wide media control integration
❌ Picture-in-picture mode
❌ Advanced power management for media

## Solutions

### For Development
The current configuration works for development and testing. The warnings can be ignored.

### For Production Release
To fully enable media playback features, you would need to:

1. Apply for special entitlements from Apple
2. Provide justification for why your terminal emulator needs these privileges
3. Go through Apple's review process
4. Use the approved entitlements in your production build

## Files

- `iTerm2.entitlements` - Standard entitlements for regular builds
- `iTerm2-Development.entitlements` - Development-specific configuration (currently same as standard)
- `iTermFileProviderNightly.entitlements` - Nightly build configuration

## Code Changes

The JavaScript transparency code has been updated to handle edge cases:

```javascript
// Check if setProperty exists before using it (fixes SVG and other special elements)
if (!isMedia && el.style && typeof el.style.setProperty === 'function') {
    el.style.setProperty('background-color', bgColor, 'important');
    el.style.setProperty('background-image', 'none', 'important');
}
```

This prevents errors on special elements (SVG, custom components) that don't support standard CSS manipulation.

## Testing

The browser should work correctly for:
- YouTube videos (with warnings in console)
- Other video streaming sites
- Audio playback
- Transparency adjustments during playback

## References

- [Apple Entitlements Documentation](https://developer.apple.com/documentation/bundleresources/entitlements)
- [WebKit Process Model](https://webkit.org/blog/7134/webassembly/)
- iTerm2 issue tracker for related discussions
