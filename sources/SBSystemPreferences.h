/*
 * SBSystemPreferences.h
 */

#import <AppKit/AppKit.h>
#import <ScriptingBridge/ScriptingBridge.h>


@class SBSystemPreferencesApplication, SBSystemPreferencesDocument, SBSystemPreferencesWindow, SBSystemPreferencesPane, SBSystemPreferencesAnchor;

enum SBSystemPreferencesSaveOptions {
	SBSystemPreferencesSaveOptionsYes = 'yes ' /* Save the file. */,
	SBSystemPreferencesSaveOptionsNo = 'no  ' /* Do not save the file. */,
	SBSystemPreferencesSaveOptionsAsk = 'ask ' /* Ask the user whether or not to save the file. */
};
typedef enum SBSystemPreferencesSaveOptions SBSystemPreferencesSaveOptions;

enum SBSystemPreferencesPrintingErrorHandling {
	SBSystemPreferencesPrintingErrorHandlingStandard = 'lwst' /* Standard PostScript error handling */,
	SBSystemPreferencesPrintingErrorHandlingDetailed = 'lwdt' /* print a detailed report of PostScript errors */
};
typedef enum SBSystemPreferencesPrintingErrorHandling SBSystemPreferencesPrintingErrorHandling;



/*
 * Standard Suite
 */

// The application's top-level scripting object.
@interface SBSystemPreferencesApplication : SBApplication

- (SBElementArray *) documents;
- (SBElementArray *) windows;

@property (copy, readonly) NSString *name;  // The name of the application.
@property (readonly) BOOL frontmost;  // Is this the active application?
@property (copy, readonly) NSString *version;  // The version number of the application.

- (id) open:(id)x;  // Open a document.
- (void) print:(id)x withProperties:(NSDictionary *)withProperties printDialog:(BOOL)printDialog;  // Print a document.
- (void) quitSaving:(SBSystemPreferencesSaveOptions)saving;  // Quit the application.
- (BOOL) exists:(id)x;  // Verify that an object exists.

@end

// A document.
@interface SBSystemPreferencesDocument : SBObject

@property (copy, readonly) NSString *name;  // Its name.
@property (readonly) BOOL modified;  // Has it been modified since the last save?
@property (copy, readonly) NSURL *file;  // Its location on disk, if it has one.

- (void) closeSaving:(SBSystemPreferencesSaveOptions)saving savingIn:(NSURL *)savingIn;  // Close a document.
- (void) saveIn:(NSURL *)in_ as:(id)as;  // Save a document.
- (void) printWithProperties:(NSDictionary *)withProperties printDialog:(BOOL)printDialog;  // Print a document.
- (void) delete;  // Delete an object.
- (void) duplicateTo:(SBObject *)to withProperties:(NSDictionary *)withProperties;  // Copy an object.
- (void) moveTo:(SBObject *)to;  // Move an object to a new location.

@end

// A window.
@interface SBSystemPreferencesWindow : SBObject

@property (copy, readonly) NSString *name;  // The title of the window.
- (NSInteger) id;  // The unique identifier of the window.
@property NSInteger index;  // The index of the window, ordered front to back.
@property NSRect bounds;  // The bounding rectangle of the window.
@property (readonly) BOOL closeable;  // Does the window have a close button?
@property (readonly) BOOL miniaturizable;  // Does the window have a minimize button?
@property BOOL miniaturized;  // Is the window minimized right now?
@property (readonly) BOOL resizable;  // Can the window be resized?
@property BOOL visible;  // Is the window visible right now?
@property (readonly) BOOL zoomable;  // Does the window have a zoom button?
@property BOOL zoomed;  // Is the window zoomed right now?
@property (copy, readonly) SBSystemPreferencesDocument *document;  // The document whose contents are displayed in the window.

- (void) closeSaving:(SBSystemPreferencesSaveOptions)saving savingIn:(NSURL *)savingIn;  // Close a document.
- (void) saveIn:(NSURL *)in_ as:(id)as;  // Save a document.
- (void) printWithProperties:(NSDictionary *)withProperties printDialog:(BOOL)printDialog;  // Print a document.
- (void) delete;  // Delete an object.
- (void) duplicateTo:(SBObject *)to withProperties:(NSDictionary *)withProperties;  // Copy an object.
- (void) moveTo:(SBObject *)to;  // Move an object to a new location.

@end



/*
 * System Preferences
 */

// System Preferences top level scripting object
@interface SBSystemPreferencesApplication (SystemPreferences)

- (SBElementArray *) panes;

@property (copy) SBSystemPreferencesPane *currentPane;  // the currently selected pane
@property (copy, readonly) SBSystemPreferencesWindow *preferencesWindow;  // the main preferences window
@property BOOL showAll;  // Is SystemPrefs in show all view. (Setting to false will do nothing)

@end

// a preference pane
@interface SBSystemPreferencesPane : SBObject

- (SBElementArray *) anchors;

- (NSString *) id;  // locale independent name of the preference pane; can refer to a pane using the expression: pane id "<name>"
@property (copy, readonly) NSString *localizedName;  // localized name of the preference pane
@property (copy, readonly) NSString *name;  // name of the preference pane as it appears in the title bar; can refer to a pane using the expression: pane "<name>"

- (void) closeSaving:(SBSystemPreferencesSaveOptions)saving savingIn:(NSURL *)savingIn;  // Close a document.
- (void) saveIn:(NSURL *)in_ as:(id)as;  // Save a document.
- (void) printWithProperties:(NSDictionary *)withProperties printDialog:(BOOL)printDialog;  // Print a document.
- (void) delete;  // Delete an object.
- (void) duplicateTo:(SBObject *)to withProperties:(NSDictionary *)withProperties;  // Copy an object.
- (void) moveTo:(SBObject *)to;  // Move an object to a new location.
- (id) reveal;  // Reveals an anchor within a preference pane or preference pane itself

@end

// an anchor within a preference pane
@interface SBSystemPreferencesAnchor : SBObject

@property (copy, readonly) NSString *name;  // name of the anchor within a preference pane

- (void) closeSaving:(SBSystemPreferencesSaveOptions)saving savingIn:(NSURL *)savingIn;  // Close a document.
- (void) saveIn:(NSURL *)in_ as:(id)as;  // Save a document.
- (void) printWithProperties:(NSDictionary *)withProperties printDialog:(BOOL)printDialog;  // Print a document.
- (void) delete;  // Delete an object.
- (void) duplicateTo:(SBObject *)to withProperties:(NSDictionary *)withProperties;  // Copy an object.
- (void) moveTo:(SBObject *)to;  // Move an object to a new location.
- (id) reveal;  // Reveals an anchor within a preference pane or preference pane itself

@end

