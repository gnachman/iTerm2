//
//  iTermTextViewContextMenuHelper.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 8/30/20.
//

#import <AppKit/AppKit.h>

#import "VT100GridTypes.h"

NS_ASSUME_NONNULL_BEGIN

@class SCPPath;
@protocol iTermObject;
@protocol VT100RemoteHostReading;
@protocol VT100ScreenMarkReading;
@protocol iTermFoldMarkReading;
@protocol iTermImageInfoReading;
@class iTermOffscreenCommandLine;
@class iTermSelection;
@class iTermSelectionReplacement;
@class iTermTextExtractor;
@class iTermTextViewContextMenuHelper;
@class iTermURLActionHelper;
@class iTermVariableScope;

// First responder can choose to implement these.
@interface NSResponder(ContextMenuHelper)
- (void)terminalStateToggleAlternateScreen:(id)sender;
- (void)terminalStateToggleFocusReporting:(id)sender;
- (void)terminalStateToggleMouseReporting:(id)sender;
- (void)terminalStateTogglePasteBracketing:(id)sender;
- (void)terminalStateToggleApplicationCursor:(id)sender;
- (void)terminalStateToggleApplicationKeypad:(id)sender;
- (void)terminalToggleKeyboardMode:(id)sender;
- (IBAction)terminalStateToggleLiteralMode:(id)sender;
- (void)terminalStateSetEmulationLevel:(id)sender;
@end

@protocol iTermContextMenuHelperDelegate<NSObject>
- (NSPoint)contextMenu:(iTermTextViewContextMenuHelper *)contextMenu
            clickPoint:(NSEvent *)event
allowRightMarginOverflow:(BOOL)allowRightMarginOverflow;

- (NSString *)contextMenuSelectedText:(iTermTextViewContextMenuHelper *)contextMenu
                               capped:(int)maxBytes;
- (NSString *)contextMenuUnstrippedSelectedText:(iTermTextViewContextMenuHelper *)contextMenu
                                         capped:(int)maxBytes;

- (id<VT100ScreenMarkReading>)contextMenu:(iTermTextViewContextMenuHelper *)contextMenu
                               markOnLine:(int)line;
- (id<VT100ScreenMarkReading>)contextMenu:(iTermTextViewContextMenuHelper *)contextMenu
                              markAtCoord:(VT100GridCoord)coord;

- (iTermOffscreenCommandLine *)contextMenu:(iTermTextViewContextMenuHelper *)contextMenu
            offscreenCommandLineForClickAt:(NSPoint)windowPoint;

- (NSString *)contextMenu:(iTermTextViewContextMenuHelper *)contextMenu
   workingDirectoryOnLine:(int)line;

- (nullable id<iTermImageInfoReading>)contextMenu:(iTermTextViewContextMenuHelper *)contextMenu
                                 imageInfoAtCoord:(VT100GridCoord)coord;

- (long long)contextMenuTotalScrollbackOverflow:(iTermTextViewContextMenuHelper *)contextMenu;

- (iTermSelection *)contextMenuSelection:(iTermTextViewContextMenuHelper *)contextMenu;
- (void)contextMenu:(iTermTextViewContextMenuHelper *)contextMenu
       setSelection:(iTermSelection *)newSelection;

- (BOOL)contextMenuSelectionIsShort:(iTermTextViewContextMenuHelper *)contextMenu;
- (BOOL)contextMenuSelectionIsReasonable:(iTermTextViewContextMenuHelper *)contextMenu;

- (iTermTextExtractor *)contextMenuTextExtractor:(iTermTextViewContextMenuHelper *)contextMenu;

- (BOOL)contextMenu:(iTermTextViewContextMenuHelper *)contextMenu
  withRelativeCoord:(VT100GridAbsCoord)coord
              block:(void (^ NS_NOESCAPE)(VT100GridCoord coord))block;
- (BOOL)contextMenu:(iTermTextViewContextMenuHelper *)contextMenu
withRelativeCoordRange:(VT100GridAbsCoordRange)range
              block:(void (^ NS_NOESCAPE)(VT100GridCoordRange))block;

- (nullable SCPPath *)contextMenu:(iTermTextViewContextMenuHelper *)contextMenu
                   scpPathForFile:(NSString *)file
                           onLine:(int)line;

- (NSArray<NSDictionary *> *)contextMenuSmartSelectionRules:(iTermTextViewContextMenuHelper *)contextMenu;
- (void)contextMenuSplitVertically:(iTermTextViewContextMenuHelper *)contextMenu;
- (void)contextMenuSplitHorizontally:(iTermTextViewContextMenuHelper *)contextMenu;
- (void)contextMenuMovePane:(iTermTextViewContextMenuHelper *)contextMenu;
- (void)contextMenu:(iTermTextViewContextMenuHelper *)contextMenu copyURL:(NSURL *)url;
- (void)contextMenuSwapSessions:(iTermTextViewContextMenuHelper *)contextMenu;
- (void)contextMenuSendSelectedText:(iTermTextViewContextMenuHelper *)contextMenu;
- (void)contextMenuClearBuffer:(iTermTextViewContextMenuHelper *)contextMenu;
- (void)contextMenuAddAnnotation:(iTermTextViewContextMenuHelper *)contextMenu;
- (BOOL)contextMenu:(iTermTextViewContextMenuHelper *)contextMenu
hasOpenAnnotationInRange:(VT100GridCoordRange)coordRange;
- (void)contextMenuRevealAnnotations:(iTermTextViewContextMenuHelper *)contextMenu
                                  at:(VT100GridCoord)coord;
- (void)contextMenuEditSession:(iTermTextViewContextMenuHelper *)contextMenu;
- (void)contextMenuToggleBroadcastingInput:(iTermTextViewContextMenuHelper *)contextMenu;
- (BOOL)contextMenuHasCoprocess:(iTermTextViewContextMenuHelper *)contextMenu;
- (void)contextMenuStopCoprocess:(iTermTextViewContextMenuHelper *)contextMenu;
- (void)contextMenuCloseSession:(iTermTextViewContextMenuHelper *)contextMenu;
- (BOOL)contextMenuSessionCanBeRestarted:(iTermTextViewContextMenuHelper *)contextMenu;
- (void)contextMenuRestartSession:(iTermTextViewContextMenuHelper *)contextMenu;
- (BOOL)contextMenuCanBurySession:(iTermTextViewContextMenuHelper *)contextMenu;
- (void)contextMenuBurySession:(iTermTextViewContextMenuHelper *)contextMenu;
- (void)contextMenu:(iTermTextViewContextMenuHelper *)contextMenu amend:(NSMenu *)menu;
- (NSControlStateValue)contextMenu:(iTermTextViewContextMenuHelper *)contextMenu
     terminalStateForMenuItem:(NSMenuItem *)item;
- (void)contextMenu:(iTermTextViewContextMenuHelper *)contextMenu
toggleTerminalStateForMenuItem:(NSMenuItem *)item;
- (void)contextMenuResetTerminal:(iTermTextViewContextMenuHelper *)contextMenu;
- (void)contextMenu:(iTermTextViewContextMenuHelper *)contextMenu addContextMenuItems:(NSMenu *)theMenu;
- (id<VT100RemoteHostReading>)contextMenu:(iTermTextViewContextMenuHelper *)contextMenu remoteHostOnLine:(int)line;
- (void)contextMenu:(iTermTextViewContextMenuHelper *)contextMenu insertText:(NSString *)text;
- (BOOL)contextMenu:(iTermTextViewContextMenuHelper *)contextMenu hasOutputForCommandMark:(id<VT100ScreenMarkReading>)commandMark;
- (VT100GridCoordRange)contextMenu:(iTermTextViewContextMenuHelper *)contextMenu
       rangeOfOutputForCommandMark:(id<VT100ScreenMarkReading>)mark;
- (void)contextMenuCopySelectionAccordingToUserPreferences:(iTermTextViewContextMenuHelper *)contextMenu;
- (void)contextMenu:(iTermTextViewContextMenuHelper *)contextMenu
copyRangeAccordingToUserPreferences:(VT100GridWindowedRange)range;

// obj is NSString or NSData
- (void)contextMenu:(iTermTextViewContextMenuHelper *)contextMenu
               copy:(id)obj;
- (void)contextMenu:(iTermTextViewContextMenuHelper *)contextMenu
replaceSelectionWith:(iTermSelectionReplacement *)replacement;
- (NSArray<iTermSelectionReplacement *> *)contextMenuSelectionReplacements:(iTermTextViewContextMenuHelper *)contextMenu;

- (void)contextMenu:(iTermTextViewContextMenuHelper *)contextMenu
 runCommandInWindow:(NSString *)command;
- (void)contextMenu:(iTermTextViewContextMenuHelper *)contextMenu
runCommandInBackground:(NSString *)command;
- (void)contextMenu:(iTermTextViewContextMenuHelper *)contextMenu
       runCoprocess:(NSString *)command;
- (void)contextMenu:(iTermTextViewContextMenuHelper *)contextMenu
            openURL:(NSURL *)url;
- (NSView *)contextMenuViewForMenu:(iTermTextViewContextMenuHelper *)contextMenu;
- (iTermVariableScope *)contextMenuSessionScope:(iTermTextViewContextMenuHelper *)contextMenu;
- (void)contextMenu:(iTermTextViewContextMenuHelper *)contextMenu
         invocation:(NSString *)invocation
    failedWithError:(NSError *)error
        forMenuItem:(NSString *)title;

- (void)contextMenu:(iTermTextViewContextMenuHelper *)contextMenu saveImage:(id<iTermImageInfoReading>)image;
- (void)contextMenu:(iTermTextViewContextMenuHelper *)contextMenu copyImage:(id<iTermImageInfoReading>)image;
- (void)contextMenu:(iTermTextViewContextMenuHelper *)contextMenu openImage:(id<iTermImageInfoReading>)image;
- (void)contextMenu:(iTermTextViewContextMenuHelper *)contextMenu inspectImage:(id<iTermImageInfoReading>)image;
- (void)contextMenu:(iTermTextViewContextMenuHelper *)contextMenu toggleAnimationOfImage:(id<iTermImageInfoReading>)image;
- (void)contextMenuSaveSelectionAsSnippet:(iTermTextViewContextMenuHelper *)contextMenu;
- (void)contextMenu:(iTermTextViewContextMenuHelper *)contextMenu addTrigger:(NSString *)text;
- (id<iTermObject>)contextMenuOwner:(iTermTextViewContextMenuHelper *)contextMenu;
- (BOOL)contextMenuSmartSelectionActionsShouldUseInterpolatedStrings:(iTermTextViewContextMenuHelper *)contextMenu;
- (void)contextMenu:(iTermTextViewContextMenuHelper *)contextMenu showCommandInfoForMark:(id<VT100ScreenMarkReading>)mark;
- (BOOL)contextMenu:(iTermTextViewContextMenuHelper *)contextMenu
    canQuickLookURL:(NSURL *)url;
- (void)contextMenuHandleQuickLook:(iTermTextViewContextMenuHelper *)contextMenu
                               url:(NSURL *)url
                  windowCoordinate:(NSPoint)windowCoordinate;
- (void)contextMenu:(iTermTextViewContextMenuHelper *)contextMenu
    removeNamedMark:(id<VT100ScreenMarkReading>)mark;
- (BOOL)contextMenuCurrentTabHasMultipleSessions:(iTermTextViewContextMenuHelper *)contextMenu;

- (void)contextMenuFoldMark:(id<VT100ScreenMarkReading>)mark;
- (void)contextMenuUnfoldMark:(id<iTermFoldMarkReading>)mark;
- (id<iTermFoldMarkReading>)contextMenuFoldAtLine:(int)line;
- (id<VT100ScreenMarkReading>)contextMenuCommandWithOutputAtLine:(int)line;
- (BOOL)contextMenuIsMouseEventReportable:(iTermTextViewContextMenuHelper *)contextMenu
                                 forEvent:(NSEvent *)event;
- (BOOL)contextMenu:(iTermTextViewContextMenuHelper *)contextMenu markShouldBeFoldable:(id<VT100ScreenMarkReading>)mark;
@end

@interface iTermTextViewContextMenuHelper : NSObject<NSMenuDelegate>
@property (nonatomic, weak) id<iTermContextMenuHelperDelegate> delegate;
@property (nonatomic, readonly, strong) iTermURLActionHelper *urlActionHelper;

// Point clicked, valid only during -validateMenuItem and calls made from
// the context menu and if x and y are nonnegative.
@property (nonatomic, readonly) VT100GridCoord validationClickPoint;

// Set when a context menu opens, nilled when it closes. If the data source changes between when we
// ask the context menu to open and when the main thread enters a tracking runloop, the text under
// the selection can change. We want to respect what we show while the context menu is open.
// See issue 4048.
@property(nullable, nonatomic, readonly) NSString *savedSelectedText;
@property (nonatomic, readonly) NSDictionary<NSNumber *, NSString *> *smartSelectionActionSelectorDictionary;

- (instancetype)initWithURLActionHelper:(iTermURLActionHelper *)urlActionHelper NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

- (NSMenu * _Nullable)menuForEvent:(NSEvent *)theEvent;
- (NSMenu *)titleBarMenu;
- (void)openContextMenuAt:(VT100GridCoord)clickPoint event:(NSEvent *)event;
- (id<VT100ScreenMarkReading> _Nullable)markForClick:(NSEvent *)event requireMargin:(BOOL)requireMargin;
- (void)selectOutputOfCommandMark:(id<VT100ScreenMarkReading>)mark;

@end

NS_ASSUME_NONNULL_END
