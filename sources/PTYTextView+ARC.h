//
//  PTYTextView+ARC.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/15/19.
//

#import "PTYTextView.h"

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

- (nullable iTermImageInfo *)imageInfoAtCoord:(VT100GridCoord)coord;
- (BOOL)imageIsVisible:(iTermImageInfo *)image;

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
- (NSDictionary *)charAttributes:(screen_char_t)c;

#pragma mark - Install Shell Integration

- (IBAction)installShellIntegration:(nullable id)sender;

#pragma mark - Mouse Reporting Frustration Detector

- (void)didCopyToPasteboardWithControlSequence;

@end

NS_ASSUME_NONNULL_END
