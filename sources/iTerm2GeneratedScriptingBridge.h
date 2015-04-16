/*
 * iTerm2.h
 */

#import <AppKit/AppKit.h>
#import <ScriptingBridge/ScriptingBridge.h>


@class iTerm2Application, iTerm2Window, iTerm2Tab, iTerm2Session;

enum iTerm2SaveOptions {
	iTerm2SaveOptionsYes = 'yes ' /* Save the file. */,
	iTerm2SaveOptionsNo = 'no  ' /* Do not save the file. */,
	iTerm2SaveOptionsAsk = 'ask ' /* Ask the user whether or not to save the file. */
};
typedef enum iTerm2SaveOptions iTerm2SaveOptions;



/*
 * Standard Suite
 */

// The application's top-level scripting object.
@interface iTerm2Application : SBApplication

- (SBElementArray *) windows;

@property (copy) iTerm2Window *currentWindow;  // The frontmost window
@property (copy, readonly) NSString *name;  // The name of the application.
@property (readonly) BOOL frontmost;  // Is this the frontmost (active) application?
@property (copy, readonly) NSString *version;  // The version of the application.

- (void) quitSaving:(iTerm2SaveOptions)saving;  // Quit the application.
- (void) createWindowWithProfile:(NSString *)x command:(NSString *)command;  // Create a new window
- (void) createWindowWithDefaultProfileCommand:(NSString *)command;  // Create a new window with the default profile

@end

// A window.
@interface iTerm2Window : SBObject

- (SBElementArray *) tabs;

@property (copy, readonly) NSString *name;  // The full title of the window.
@property NSInteger index;  // The index of the window, ordered front to back.
@property NSRect bounds;  // The bounding rectangle of the window.
@property (readonly) BOOL closeable;  // Whether the window has a close box.
@property (readonly) BOOL miniaturizable;  // Whether the window can be minimized.
@property BOOL miniaturized;  // Whether the window is currently minimized.
@property (readonly) BOOL resizable;  // Whether the window can be resized.
@property BOOL visible;  // Whether the window is currently visible.
@property (readonly) BOOL zoomable;  // Whether the window can be zoomed.
@property BOOL zoomed;  // Whether the window is currently zoomed.
@property BOOL frontmost;  // Whether the window is currently the frontmost window.
@property (copy) iTerm2Tab *currentTab;  // The currently selected tab
@property (copy) iTerm2Session *currentSession;  // The current session in a window
@property NSPoint position;  // The position of the window, relative to the upper left corner of the screen.
@property NSPoint origin;  // The position of the window, relative to the lower left corner of the screen.
@property NSPoint size;  // The width and height of the window
@property NSRect frame;  // The bounding rectangle, relative to the lower left corner of the screen.

- (void) delete;  // Delete an object.
- (void) duplicateTo:(SBObject *)to withProperties:(NSDictionary *)withProperties;  // Copy object(s) and put the copies at a new location.
- (BOOL) exists;  // Verify if an object exists.
- (void) moveTo:(SBObject *)to;  // Move object(s) to a new location.
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



/*
 * iTerm2 Suite
 */

// A terminal tab
@interface iTerm2Tab : SBObject

- (SBElementArray *) sessions;

@property (copy) iTerm2Session *currentSession;  // The current session in a tab
@property NSInteger index;  // Index of tab in parent tab view control

- (void) delete;  // Delete an object.
- (void) duplicateTo:(SBObject *)to withProperties:(NSDictionary *)withProperties;  // Copy object(s) and put the copies at a new location.
- (BOOL) exists;  // Verify if an object exists.
- (void) moveTo:(SBObject *)to;  // Move object(s) to a new location.
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
@property BOOL isAtShellPrompt;  // The terminal is at the shell prompt. Requires shell integration.
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

- (void) delete;  // Delete an object.
- (void) duplicateTo:(SBObject *)to withProperties:(NSDictionary *)withProperties;  // Copy object(s) and put the copies at a new location.
- (BOOL) exists;  // Verify if an object exists.
- (void) moveTo:(SBObject *)to;  // Move object(s) to a new location.
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

