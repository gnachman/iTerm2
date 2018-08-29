#import <Cocoa/Cocoa.h>

#import "WindowControllerInterface.h"
#import "PTYSession.h"

@class iTermLibSessionController;

@protocol iTermLibSessionDelegate <NSObject>

- (NSArray<iTermLibSessionController*>*)sessions;
- (NSArray<PTYSession*>*)allPTYSessions;
- (PTYSession*)activePTYSession;
- (void)setActivePTYSession:(PTYSession*)session;
- (void)ptySessionDidTerminate:(PTYSession*)session;
- (iTermLibSessionController*)sessionControllerForPTYSession:(PTYSession*)session;
- (void)shouldRemovePTYSession:(PTYSession*)session;
- (BOOL)broadcasting;
- (void)setBroadcasting:(BOOL)value;
- (void)nameOfSession:(PTYSession*)session didChangeTo:(NSString*)newName;

@end

@interface iTermLibSessionController : NSObject<iTermWindowController, WindowControllerInterface, PTYSessionDelegate>

- (instancetype)initWithProfile:(Profile*)profile command:(NSString*)command initialSize:(NSSize)initialSize;

+ (Profile*)defaultProfile;

@property (assign) id<iTermLibSessionDelegate> delegate;

@property (readonly) PTYSession* session;
@property (readonly) NSView* view;

@property (readonly, assign) BOOL wasActive;

@property (assign) BOOL highlightCursorLine;
@property (assign) BOOL showTimestamps;
@property (assign) BOOL logging;
@property (readonly) BOOL showAnnotations;
@property (readonly) NSImage* screenshot;
@property (readonly) BOOL shellIntegrationIsInstalled;

- (void)focus;
- (void)terminate;

- (void)showFindPanel;
- (void)findCursor;

- (void)paste;
- (void)pasteSlowly;
- (void)pasteEscapingSpecialCharacters;
- (void)pasteAdvanced;

- (void)clearBuffer;
- (void)clearScrollbackBuffer;

- (void)openAutocomplete;

- (void)setMark;
- (void)addAnnotationAtCursor;
- (void)toggleShowAnnotations;
- (void)jumpToMark;
- (void)jumpToNextMark;
- (void)jumpToPreviousMark;
- (void)jumpToSelection;

- (void)selectAll;
- (void)selectOutputOfLastCommand;
- (void)selectCurrentCommand;

- (void)increaseFontSize;
- (void)decreaseFontSize;
- (void)restoreFontSize;

- (void)tryToRunShellIntegrationInstallerWithPromptCheck:(BOOL)promptCheck;

@end
