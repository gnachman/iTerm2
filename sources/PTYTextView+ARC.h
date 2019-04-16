//
//  PTYTextView+ARC.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/15/19.
//

#import "PTYTextView.h"

#import "iTermURLActionHelper.h"
#import "VT100GridTypes.h"

@class URLAction;

NS_ASSUME_NONNULL_BEGIN

@interface PTYTextView (ARC)<iTermURLActionHelperDelegate>

#pragma mark - Coordinate Space Conversions

- (NSPoint)clickPoint:(NSEvent *)event allowRightMarginOverflow:(BOOL)allowRightMarginOverflow;

- (NSPoint)windowLocationToRowCol:(NSPoint)locationInWindow
         allowRightMarginOverflow:(BOOL)allowRightMarginOverflow;

- (VT100GridCoord)coordForPoint:(NSPoint)locationInTextView
       allowRightMarginOverflow:(BOOL)allowRightMarginOverflow;

- (NSPoint)pointForCoord:(VT100GridCoord)coord;

- (VT100GridCoord)coordForPointInWindow:(NSPoint)point;

#pragma mark - Query Coordinates

- (iTermImageInfo *)imageInfoAtCoord:(VT100GridCoord)coord;

#pragma mark - Open URL

- (NSDictionary<NSNumber *, NSString *> *)smartSelectionActionSelectorDictionary;

#pragma mark - Semantic History

- (void)handleSemanticHistoryItemDragWithEvent:(NSEvent *)event
                                         coord:(VT100GridCoord)coord;

#pragma mark - Underlined Actions

- (void)updateUnderlinedURLs:(NSEvent *)event;

#pragma mark - Context Menu Actions

- (void)contextMenuActionOpenFile:(id)sender;
- (void)contextMenuActionOpenURL:(id)sender;
- (void)contextMenuActionRunCommand:(id)sender;
- (void)contextMenuActionRunCommandInWindow:(id)sender;
+ (void)runCommand:(NSString *)command;
- (void)contextMenuActionRunCoprocess:(id)sender;
- (void)contextMenuActionSendText:(id)sender;

#pragma mark - Mouse Cursor

- (void)updateCursor:(NSEvent *)event action:(nullable URLAction *)action;
- (BOOL)setCursor:(NSCursor *)cursor;
- (BOOL)mouseIsOverImageInEvent:(NSEvent *)event;

#pragma mark - Mouse Reporting

- (BOOL)xtermMouseReporting;
- (BOOL)xtermMouseReportingAllowMouseWheel;
- (BOOL)terminalWantsMouseReports;

#pragma mark - Quicklook

- (void)handleQuickLookWithEvent:(NSEvent *)event;

#pragma mark - Copy to Pasteboard

// Returns a dictionary to pass to NSAttributedString.
- (NSDictionary *)charAttributes:(screen_char_t)c;

@end

NS_ASSUME_NONNULL_END
