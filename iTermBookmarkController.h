//
//  untitled.h
//  iTerm
//
//  Created by Tianming Yang on 10/11/06.
//  Copyright 2006 __MyCompanyName__. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@class iTermController;
@class TreeNode;

@interface iTermBookmarkController : NSWindowController {
    NSUserDefaults *_prefs;

	// Bookmark stuff
	IBOutlet NSOutlineView *bookmarksView;
	IBOutlet NSPanel *addBookmarkFolderPanel;
	IBOutlet NSPanel *deleteBookmarkPanel;
	IBOutlet NSPanel *editBookmarkPanel;
	IBOutlet NSButton *bookmarkDeleteButton;
	IBOutlet NSButton *bookmarkEditButton;
	IBOutlet NSSegmentedControl *launchButton;
	IBOutlet NSTextField *bookmarkFolderName;
	IBOutlet NSTextField *bookmarkName;
	IBOutlet NSTextField *bookmarkCommand;
	IBOutlet NSTextField *bookmarkWorkingDirectory;
	IBOutlet NSPopUpButton *bookmarkShortcut;
	IBOutlet NSPopUpButton *bookmarkTerminalProfile;
	IBOutlet NSPopUpButton *bookmarkKeyboardProfile;
	IBOutlet NSPopUpButton *bookmarkDisplayProfile;
	NSArray	 		*draggedNodes;
	IBOutlet NSButton *defaultSessionButton;
	IBOutlet NSTextField *addFolderPanelTitle;
}

+ (iTermBookmarkController*)sharedInstance;

- (id)initWithWindowNibName: (NSString *) windowNibName;
- (void)dealloc;

- (void) showWindow;

- (IBAction) addBookmarkFolder: (id) sender;
- (IBAction) addBookmarkFolderConfirm: (id) sender;
- (IBAction) addBookmarkFolderCancel: (id) sender;
- (IBAction) addBookmark: (id) sender;
- (IBAction) addBookmarkConfirm: (id) sender;
- (IBAction) addBookmarkCancel: (id) sender;
- (IBAction) deleteBookmark: (id) sender;
- (IBAction) editBookmark: (id) sender;
- (IBAction) sortBookmark: (id) sender;
- (IBAction) setDefaultSession: (id) sender;
- (IBAction) launchSession: (id) sender;
@end

@interface iTermBookmarkController (Private)

- (void)_addBookmarkFolderSheetDidEnd:(NSWindow *)sheet returnCode:(int)returnCode contextInfo:(void *)contextInfo;
- (void)_deleteBookmarkSheetDidEnd:(NSWindow *)sheet returnCode:(int)returnCode contextInfo:(void *)contextInfo;
- (void)_editBookmarkSheetDidEnd:(NSWindow *)sheet returnCode:(int)returnCode contextInfo:(void *)contextInfo;
- (NSArray*) _draggedNodes;
- (NSArray *) _selectedNodes;
- (void)_performDropOperation:(id <NSDraggingInfo>)info onNode:(TreeNode*)parentNode atIndex:(int)childIndex;
- (void) _loadProfiles;

@end
