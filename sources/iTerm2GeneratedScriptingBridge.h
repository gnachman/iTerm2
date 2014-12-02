/*
 * iTerm2.h
 */

#import <AppKit/AppKit.h>
#import <ScriptingBridge/ScriptingBridge.h>


@class iTerm2Application, iTerm2TerminalWindow, iTerm2Tab, iTerm2Session;



/*
 * iTerm2 Suite
 */

// The application's top-level scripting object.
@interface iTerm2Application : SBApplication

- (SBElementArray *) terminalWindows;

@property (copy) iTerm2TerminalWindow *currentWindow;  // The frontmost window

- (void) createWindowWithProfile:(NSString *)x command:(NSString *)command;  // Create a new window
- (void) createWindowWithDefaultProfileCommand:(NSString *)command;  // Create a new window with the default profile

@end

// A terminal window
@interface iTerm2TerminalWindow : SBObject

- (SBElementArray *) tabs;

@property (copy) iTerm2Tab *currentTab;  // The currently selected tab
@property (copy) iTerm2Session *currentSession;  // The current session in a window

- (void) close;  // Close a document.
- (void) createTabWithProfile:(NSString *)withProfile command:(NSString *)command;  // Create a new tab
- (void) createTabWithDefaultProfileCommand:(NSString *)command;  // Create a new tab with the default profile
- (void) writeContentsOfFile:(NSURL *)contentsOfFile text:(NSString *)text;  // Send text as though it was typed.
- (void) select;  // Make receiver visible and selected.
- (void) splitVerticallyWithProfile:(NSString *)withProfile;  // Split a session vertically.
- (void) splitVerticallyWithDefaultProfile;  // Split a session vertically, using the default profile for the new session
- (void) splitVerticallyWithSameProfile;  // Split a session vertically, using the original session's profile for the new session
- (void) splitHorizontallyWithProfile:(NSString *)withProfile;  // Split a session horizontally.
- (void) splitHorizontallyWithDefaultProfile;  // Split a session horizontally, using the default profile for the new session
- (void) splitHorizontallyWithSameProfile;  // Split a session horizontally, using the original session's profile for the new session

@end

// A terminal tab
@interface iTerm2Tab : SBObject

- (SBElementArray *) sessions;

@property (copy) iTerm2Session *currentSession;  // The current session in a tab
@property NSInteger index;  // Index of tab in parent tab view control

- (void) close;  // Close a document.
- (void) createTabWithProfile:(NSString *)withProfile command:(NSString *)command;  // Create a new tab
- (void) createTabWithDefaultProfileCommand:(NSString *)command;  // Create a new tab with the default profile
- (void) writeContentsOfFile:(NSURL *)contentsOfFile text:(NSString *)text;  // Send text as though it was typed.
- (void) select;  // Make receiver visible and selected.
- (void) splitVerticallyWithProfile:(NSString *)withProfile;  // Split a session vertically.
- (void) splitVerticallyWithDefaultProfile;  // Split a session vertically, using the default profile for the new session
- (void) splitVerticallyWithSameProfile;  // Split a session vertically, using the original session's profile for the new session
- (void) splitHorizontallyWithProfile:(NSString *)withProfile;  // Split a session horizontally.
- (void) splitHorizontallyWithDefaultProfile;  // Split a session horizontally, using the default profile for the new session
- (void) splitHorizontallyWithSameProfile;  // Split a session horizontally, using the original session's profile for the new session

@end

// A terminal session
@interface iTerm2Session : SBObject

@property BOOL isProcessing;  // The session has received output recently.
@property NSInteger columns;
@property NSInteger rows;
@property (copy, readonly) NSString *tty;
@property (copy) NSString *contents;
@property (copy) NSColor *backgroundColor;
@property (copy) NSColor *boldColor;
@property (copy) NSColor *cursorColor;
@property (copy) NSColor *cursorTextColor;
@property (copy) NSColor *foregroundColor;
@property (copy) NSColor *selectedTextColor;
@property (copy) NSColor *selectionColor;
@property (copy) NSColor *ANSIBlackColor;
@property (copy) NSColor *ANSIRedColor;
@property (copy) NSColor *ANSIGreenColor;
@property (copy) NSColor *ANSIYellowColor;
@property (copy) NSColor *ANSIBlueColor;
@property (copy) NSColor *ANSIMagentaColor;
@property (copy) NSColor *ANSICyanColor;
@property (copy) NSColor *ANSIWhiteColor;
@property (copy) NSColor *ANSIBrightBlackColor;
@property (copy) NSColor *ANSIBrightRedColor;
@property (copy) NSColor *ANSIBrightGreenColor;
@property (copy) NSColor *ANSIBrightYellowColor;
@property (copy) NSColor *ANSIBrightBlueColor;
@property (copy) NSColor *ANSIBrightMagentaColor;
@property (copy) NSColor *ANSIBrightCyanColor;
@property (copy) NSColor *ANSIBrightWhiteColor;
@property (copy) NSString *backgroundImage;
@property (copy) NSString *name;
@property double transparency;
@property (copy, readonly) NSString *uniqueID;

- (void) close;  // Close a document.
- (void) createTabWithProfile:(NSString *)withProfile command:(NSString *)command;  // Create a new tab
- (void) createTabWithDefaultProfileCommand:(NSString *)command;  // Create a new tab with the default profile
- (void) writeContentsOfFile:(NSURL *)contentsOfFile text:(NSString *)text;  // Send text as though it was typed.
- (void) select;  // Make receiver visible and selected.
- (void) splitVerticallyWithProfile:(NSString *)withProfile;  // Split a session vertically.
- (void) splitVerticallyWithDefaultProfile;  // Split a session vertically, using the default profile for the new session
- (void) splitVerticallyWithSameProfile;  // Split a session vertically, using the original session's profile for the new session
- (void) splitHorizontallyWithProfile:(NSString *)withProfile;  // Split a session horizontally.
- (void) splitHorizontallyWithDefaultProfile;  // Split a session horizontally, using the default profile for the new session
- (void) splitHorizontallyWithSameProfile;  // Split a session horizontally, using the original session's profile for the new session

@end

