//
//  PTYTextView+ARC.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/15/19.
//

#import "PTYTextView.h"

#import "iTermSnippetsModel.h"
#import "iTermTextViewContextMenuHelper.h"
#import "iTermMouseReportingFrustrationDetector.h"
#import "iTermURLActionHelper.h"
#import "VT100GridTypes.h"

@class ContentNavigationShortcutView;
@protocol PTYTrackingChildWindow;
@class URLAction;
@protocol iTermContentNavigationShortcutView;

NS_ASSUME_NONNULL_BEGIN

@interface PTYTextView (ARC)<
iTermContextMenuHelperDelegate,
iTermMouseReportingFrustrationDetectorDelegate,
iTermURLActionHelperDelegate>

- (void)initARC;

#pragma mark - NSResponder

- (BOOL)arcValidateMenuItem:(NSMenuItem *)item;

#pragma mark - Coordinate Space Conversions

- (NSPoint)clickPoint:(NSEvent *)event allowRightMarginOverflow:(BOOL)allowRightMarginOverflow;

- (NSPoint)windowLocationToRowCol:(NSPoint)locationInWindow
         allowRightMarginOverflow:(BOOL)allowRightMarginOverflow;

- (VT100GridCoord)coordForPoint:(NSPoint)locationInTextView
       allowRightMarginOverflow:(BOOL)allowRightMarginOverflow;

- (NSPoint)pointForCoord:(VT100GridCoord)coord;

- (VT100GridCoord)coordForPointInWindow:(NSPoint)point;

#pragma mark - Inline Images

- (nullable id<iTermImageInfoReading>)imageInfoAtCoord:(VT100GridCoord)coord;
- (BOOL)imageIsVisible:(id<iTermImageInfoReading>)image;

#pragma mark - Semantic History

- (void)handleSemanticHistoryItemDragWithEvent:(NSEvent *)event
                                         coord:(VT100GridCoord)coord;

#pragma mark - Underlined Actions

- (void)updateUnderlinedURLs:(NSEvent *)event;

#pragma mark - Context Menu

- (NSMenu *)menuForEvent:(NSEvent *)event;

#pragma mark - Offscreen Command Line

- (iTermOffscreenCommandLine *)offscreenCommandLineForClickAt:(NSPoint)windowPoint;
- (void)presentCommandInfoForOffscreenCommandLine:(iTermOffscreenCommandLine *)offscreenCommandLine
                                            event:(NSEvent *)event;
- (void)presentCommandInfoForMark:(id<VT100ScreenMarkReading>)mark
               absoluteLineNumber:(long long)absoluteLineNumber
                             date:(NSDate *)date
                            event:(NSEvent *)event;
#pragma mark - Mouse Cursor

// Returns whether any change was made.
- (BOOL)updateCursor:(NSEvent *)event action:(nullable URLAction *)action;
- (BOOL)setCursor:(NSCursor *)cursor;
- (BOOL)mouseIsOverImageInEvent:(NSEvent *)event;

#pragma mark - Quicklook

- (void)handleQuickLookWithEvent:(NSEvent *)event;

#pragma mark - Copy to Pasteboard

// Returns a dictionary to pass to NSAttributedString.
- (NSDictionary *)charAttributes:(screen_char_t)c
              externalAttributes:(iTermExternalAttribute *)ea
                       processed:(BOOL)processed;

#pragma mark - Install Shell Integration

- (IBAction)installShellIntegration:(nullable id)sender;

#pragma mark - Mouse Reporting Frustration Detector

- (void)didCopyToPasteboardWithControlSequence;

#pragma mark - Indicator Messages

- (void)showIndicatorMessage:(NSString *)message at:(NSPoint)point;

#pragma mark - Selected Text

// A rough heuristic for whether it will be noticeably slow to extract the selection to a string.
- (BOOL)selectionIsBig;
- (BOOL)selectionIsBig:(iTermSelection *)selection;

// Saves the selection as the "last" selection app-wide and returns a promise in case you need the value.
- (iTermPromise<NSString *> *)recordSelection:(iTermSelection *)selection;

- (id)selectedTextWithStyle:(iTermCopyTextStyle)style
               cappedAtSize:(int)maxBytes
          minimumLineNumber:(int)minimumLineNumber
                 timestamps:(BOOL)timestamps
                  selection:(iTermSelection *)selection;

- (NSAttributedString *)selectedAttributedTextWithPad:(BOOL)pad;
- (NSAttributedString *)selectedAttributedTextWithPad:(BOOL)pad
                                            selection:(iTermSelection *)selection;

- (NSString *)selectedTextCappedAtSize:(int)maxBytes
                     minimumLineNumber:(int)minimumLineNumber;

- (void)asynchronouslyVendSelectedTextWithStyle:(iTermCopyTextStyle)style
                                   cappedAtSize:(int)maxBytes
                              minimumLineNumber:(int)minimumLineNumber
                                      selection:(iTermSelection *)selection;

#pragma mark - Find on Page

- (void)convertMatchesToSelections;

#pragma mark - Tracking Child Windows

- (void)trackChildWindow:(id<PTYTrackingChildWindow>)window;
- (void)shiftTrackingChildWindows;

#pragma mark - Content Navigation Shortcuts

- (void)convertVisibleSearchResultsToContentNavigationShortcuts;

- (ContentNavigationShortcutView *)addShortcutWithRange:(VT100GridAbsCoordRange)range
                                          keyEquivalent:(NSString *)keyEquivalent
                                                 action:(void (^)(id<iTermContentNavigationShortcutView>))action;
- (void)removeContentNavigationShortcuts;

// This is meant to be used after the view finishes animating.
- (void)removeContentNavigationShortcutView:(id<iTermContentNavigationShortcutView>)view;

@end

NS_ASSUME_NONNULL_END
