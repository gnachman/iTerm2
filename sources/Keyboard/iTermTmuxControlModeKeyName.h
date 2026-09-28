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

/// Returns the tmux send-keys key name for any keystroke tmux can encode, for a
/// server that encodes every key itself (see -[TmuxGateway serverEncodesAllKeys]).
/// Unlike iTermTmuxControlModeOtherKeyName, this also names the keys whose
/// encoding depends on the pane's mode but which the byte path would send
/// verbatim: unmodified Enter, Tab, Escape and Backspace, Shift+Tab, and arrow,
/// navigation and F1-F12 keys. tmux then encodes each one for the pane's current
/// mode (legacy, modifyOtherKeys, or the Kitty keyboard protocol), which it
/// tracks per pane and keeps across a detach.
///
/// Returns nil to keep the byte path, which also hands printable text to tmux's
/// key encoder, for:
///   - text: an unmodified or shifted printable, or option composing a character,
///   - numeric keypad keys and F13 and up, which tmux drops in any mode but
///     Kitty,
///   - keys tmux has no name for, and
///   - unless modifyOtherKeys is YES, Control with Escape, Backspace or one of
///     # $ % & *. tmux has no VT10x encoding for those, and send-keys types the
///     name as text when the pane's mode cannot encode a key (a deliberate
///     choice, tmux commit 04eee241, shipped in 3.1) rather than dropping it.
///     They encode fine in modifyOtherKeys mode, which the pane requests through
///     output we parse as tmux does, so the caller passes YES when the pane has
///     asked for level 1 or 2 and the keys are named only then.
///
/// Option is always reported as M- on the non-text keys, matching the byte path,
/// which passes it through as a modifier on arrow and function keys whatever the
/// option key setting. On printable keys it is M- only when option acts as meta.
NSString * _Nullable iTermTmuxControlModeKeyName(UTF32Char codePoint,
                                                 NSEventModifierFlags modifiers,
                                                 BOOL optionActsAsMeta,
                                                 BOOL isNumericKeypad,
                                                 BOOL modifyOtherKeys);

// Implemented by the key mappers that can name a modifyOtherKeys "other key"
// for a tmux -CC pane (the modifyOtherKeys level 1 and level 2 mappers).
@protocol iTermTmuxControlModeKeyNaming<NSObject>

// Returns the tmux send-keys key name (e.g. @"C-j", @"S-Enter") for this
// keystroke if it should be delegated to tmux, or nil to use the byte path.
- (nullable NSString *)tmuxControlModeKeyNameForEvent:(NSEvent *)event;

@end

NS_ASSUME_NONNULL_END
