//
//  iTermTmuxControlModeKeyName.h
//  iTerm2SharedARC
//
//  Maps a keystroke that the modifyOtherKeys mapper would encode as a
//  modifyOtherKeys "other key" (ESC [ 27 ; mod ; key ~) to the tmux send-keys
//  key-name argument for it, so a tmux -CC pane can be handed the semantic key
//  and let tmux re-encode it in the pane's own mode + extended-keys-format.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

/// Returns the tmux send-keys key-name argument (e.g. @"C-j", @"S-Enter",
/// @"C-S-J", @"C-Space") for a keystroke that iTerm2's modifyOtherKeys mapper
/// would otherwise expand into an ESC [ 27 ; mod ; key ~ sequence, so tmux can
/// re-encode it in the pane's own extended-keys-format. This is the single
/// source of truth for the "should we delegate, and if so as what name" policy;
/// it must mirror the byte path (stringForEvent / keyMapperStringForPreCocoaEvent
/// in iTermModifyOtherKeysMapper.m).
///
/// Returns nil when the key should keep the byte-injection path, i.e. the byte
/// path would NOT encode it as ESC[27;m;k~:
///   - an application-keypad key (isNumericKeypad) whose SS3/CSI keypad encoding
///     is format-independent, or
///   - no encodable modifier (Control/Option/Shift) is set, or
///   - a function / navigation key (arrows, Home, End, PageUp, PageDown, Insert,
///     Delete, F-keys) or a non-nameable control code, or
///   - a plain shifted printable (Shift+1 -> "!") inserted as text, or option
///     composing a character (optionActsAsMeta is NO).
///
/// The keystrokes that ARE delegated: Control+anything, option acting as meta,
/// the command keys Return/Tab/Escape/Backspace (never inserted as text), and
/// Shift+Space when Shift is the sole modifier. Command is not a modifyOtherKeys
/// modifier: it is ignored. Modifier prefixes are emitted in a fixed C-, M-, S-
/// order; tmux accepts them in any order.
NSString * _Nullable iTermTmuxControlModeOtherKeyName(UTF32Char codePoint,
                                                      NSEventModifierFlags modifiers,
                                                      BOOL optionActsAsMeta,
                                                      BOOL isNumericKeypad);

// Implemented by the key mappers that can name a modifyOtherKeys "other key"
// for a tmux -CC pane (the modifyOtherKeys level 1 and level 2 mappers).
@protocol iTermTmuxControlModeKeyNaming<NSObject>

// Returns the tmux send-keys key name (e.g. @"C-j", @"S-Enter") for this
// keystroke if it should be delegated to tmux, or nil to use the byte path.
- (nullable NSString *)tmuxControlModeKeyNameForEvent:(NSEvent *)event;

@end

NS_ASSUME_NONNULL_END
