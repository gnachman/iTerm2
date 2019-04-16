//
//  PTYTextView+ARC.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/15/19.
//

#import "PTYTextView.h"

#import "VT100GridTypes.h"

@class URLAction;

NS_ASSUME_NONNULL_BEGIN

@interface PTYTextView (ARC)

#pragma mark - Attributes

- (NSColor *)selectionBackgroundColor;
- (NSColor *)selectedTextColor;

#pragma mark - Coordinate Space Conversions

- (NSPoint)clickPoint:(NSEvent *)event allowRightMarginOverflow:(BOOL)allowRightMarginOverflow;

- (NSPoint)windowLocationToRowCol:(NSPoint)locationInWindow
         allowRightMarginOverflow:(BOOL)allowRightMarginOverflow;

- (VT100GridCoord)coordForPoint:(NSPoint)locationInTextView
       allowRightMarginOverflow:(BOOL)allowRightMarginOverflow;

#pragma mark - Query Coordinates

- (iTermImageInfo *)imageInfoAtCoord:(VT100GridCoord)coord;

#pragma mark - URL Actions

- (BOOL)ignoreHardNewlinesInURLs;

- (URLAction *)urlActionForClickAtX:(int)x y:(int)y;

- (void)urlActionForClickAtX:(int)x
                           y:(int)y
      respectingHardNewlines:(BOOL)respectHardNewlines
                  completion:(void (^)(URLAction *))completion;

- (void)openTargetWithEvent:(NSEvent *)event inBackground:(BOOL)openInBackground;

- (void)findUrlInString:(NSString *)aURLString andOpenInBackground:(BOOL)background;

#pragma mark Secure Copy

+ (NSString *)usernameToDownloadFileOnHost:(NSString *)host;

- (void)downloadFileAtSecureCopyPath:(SCPPath *)scpPath
                         displayName:(NSString *)name
                      locationInView:(VT100GridCoordRange)range;

#pragma mark - Open URL

- (void)openURL:(NSURL *)url inBackground:(BOOL)background;

- (NSDictionary<NSNumber *, NSString *> *)smartSelectionActionSelectorDictionary;

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

@end

NS_ASSUME_NONNULL_END
