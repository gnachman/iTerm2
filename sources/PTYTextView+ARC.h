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

@class URLAction;

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

#pragma mark - Mouse Cursor

// Returns whether any change was made.
- (BOOL)updateCursor:(NSEvent *)event action:(nullable URLAction *)action;
- (BOOL)setCursor:(NSCursor *)cursor;
- (BOOL)mouseIsOverImageInEvent:(NSEvent *)event;

#pragma mark - Quicklook

- (void)handleQuickLookWithEvent:(NSEvent *)event;

#pragma mark - Copy to Pasteboard

// Returns a dictionary to pass to NSAttributedString.
- (NSDictionary *)charAttributes:(screen_char_t)c externalAttributes:(iTermExternalAttribute *)ea;

#pragma mark - Install Shell Integration

- (IBAction)installShellIntegration:(nullable id)sender;

#pragma mark - Mouse Reporting Frustration Detector

- (void)didCopyToPasteboardWithControlSequence;

#pragma mark - Indicator Messages

- (void)showIndicatorMessage:(NSString *)message at:(NSPoint)point;

#pragma mark - Selected Text

// A rough heuristic for whether it will be noticeably slow to extract the selection to a string.
- (BOOL)selectionIsBig;

// Saves the selection as the "last" selection app-wide and returns a promise in case you need the value.
- (iTermPromise<NSString *> *)recordSelection;

- (id)selectedTextWithStyle:(iTermCopyTextStyle)style
               cappedAtSize:(int)maxBytes
          minimumLineNumber:(int)minimumLineNumber;

- (NSAttributedString *)selectedAttributedTextWithPad:(BOOL)pad;

- (NSString *)selectedTextCappedAtSize:(int)maxBytes
                     minimumLineNumber:(int)minimumLineNumber;

- (void)asynchronouslyVendSelectedTextWithStyle:(iTermCopyTextStyle)style
                                   cappedAtSize:(int)maxBytes
                              minimumLineNumber:(int)minimumLineNumber;

@end

NS_ASSUME_NONNULL_END
