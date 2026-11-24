//
//  PSMYosemiteTabStyle.h
//  PSMTabBarControl
//
//  Created by John Pannell on 2/17/06.
//  Copyright 2006 Positive Spin Media. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "PSMTabStyle.h"
#import "PSMTabBarControl.h"

NS_ASSUME_NONNULL_BEGIN

extern const void *PSMTabStyleLightColorKey;
extern const void *PSMTabStyleDarkColorKey;

extern BOOL gDebugLogging;
int DebugLogImpl(const char *file, int line, const char *function, NSString* value);
// A copy of DLog in sources/Logging/DebugLogging.h (PSMRolloverButton.m has a third). A unit
// gets whichever definition it saw last, and for many app files that is this one. The copies
// must stay token-identical: changing only one gives a macro-redefined warning, and the units
// that see the other copy keep the old behavior.
#define DLog(args...) \
    do { \
        if (gDebugLogging) { \
            DebugLogImpl(__FILE__, __LINE__, __FUNCTION__, [NSString stringWithFormat:args]); \
        } \
    } while (0)

// __cyclicLog should be an instance of iTermCyclicLog
// Unlike DLog, the message is formatted on every call, even when debug logging is off, because
// the cyclic log always records it. Its user is sources/StateRestoration/iTermGraphDatabase.m.
#define DLogCyclic(__cyclicLog, args...) \
    do { \
        NSString *__formatted = [NSString stringWithFormat:args]; \
        if (gDebugLogging) { \
            DebugLogImpl(__FILE__, __LINE__, __FUNCTION__, __formatted); \
        } \
        [__cyclicLog log:[NSString stringWithFormat:@"%s:%d: %@", __FILE__, __LINE__, __formatted]]; \
    } while (0)

@interface NSColor (HSP)
@property (nonatomic, readonly) CGFloat it_hspBrightness;
@end

@interface PSMYosemiteTabStyle : NSObject<PSMTabStyle>

@property(nonatomic, readonly, nullable) NSColor *tabBarColor;
@property(nonatomic) PSMTabBarOrientation orientation;
@property(nonatomic, readonly) BOOL windowIsMainAndAppIsActive;

#pragma mark - For subclasses

- (NSColor *)topLineColorSelected:(BOOL)selected;
- (BOOL)anyTabHasColor;
// Where rich content lines are drawn in a cell. Unlike the classic title, it
// doesn't depend on the title's length.
- (NSRect)richContentRectForCell:(PSMTabBarCell *)cell
                   labelPosition:(CGFloat)labelPosition
                         hasIcon:(BOOL)hasIcon
                        iconRect:(NSRect)iconRect
                   reservedSpace:(CGFloat)reservedSpace;
// Where the status dot or other attention icon goes.
- (NSRect)iconRectForTabCell:(PSMTabBarCell *)cell;
- (CGFloat)tabColorBrightness:(PSMTabBarCell *)cell;
// Which of a rich line's light and dark colors to use in this cell.
- (nullable NSAppearance *)richLineColorAppearanceForCell:(PSMTabBarCell *)cell;
- (NSEdgeInsets)insetsForTabBarDividers;
- (NSEdgeInsets)backgroundInsetsWithHorizontalOrientation:(BOOL)horizontal;

- (NSColor *)effectiveBackgroundColorForTabWithTabColor:(NSColor *)tabColor
                                               selected:(BOOL)selected
                                        highlightAmount:(CGFloat)highlightAmount
                                                 window:(NSWindow * _Nullable)window;
- (void)drawCellBackgroundSelected:(BOOL)selected
                            inRect:(NSRect)cellFrame
                      withTabColor:(NSColor * _Nullable)tabColor
                   highlightAmount:(CGFloat)highlightAmount
                        horizontal:(BOOL)horizontal;
- (void)drawShadowForUnselectedTabInRect:(NSRect)backgroundRect;

- (void)drawSubtitle:(PSMCachedTitle * _Nullable)cachedSubtitle
                   x:(CGFloat)labelPosition
                cell:(PSMTabBarCell *)cell
             hasIcon:(BOOL)drewIcon
            iconRect:(NSRect)iconRect
       reservedSpace:(CGFloat)reservedSpace
           cellFrame:(NSRect)cellFrame
         labelOffset:(CGFloat)labelOffset
     mainLabelHeight:(CGFloat)mainLabelHeight;

- (CGFloat)widthForLabelInCell:(PSMTabBarCell *)cell
                 labelPosition:(CGFloat)labelPosition
                       hasIcon:(BOOL)drewIcon
                      iconRect:(NSRect)iconRect
                   cachedTitle:(PSMCachedTitle * _Nullable)cachedTitle
                 reservedSpace:(CGFloat)reservedSpace
                  boundingSize:(NSSize * _Nullable)boundingSizeOut
                      truncate:(BOOL * _Nullable)truncateOut;

- (BOOL)willDrawSubtitle:(PSMCachedTitle * _Nullable)subtitle;
- (CGFloat)verticalOffsetForTitleWhenSubtitlePresent;
- (CGFloat)verticalOffsetForSubtitle;

- (BOOL)shouldDrawTopLineSelected:(BOOL)selected
                         attached:(BOOL)attached
                         position:(PSMTabPosition)position;

@end

@interface PSMTabBarCell(PSMYosemiteTabStyle)

@property(nonatomic, nullable) NSAttributedString *previousAttributedString;
@property(nonatomic) CGFloat previousWidthOfAttributedString;

@end

NS_ASSUME_NONNULL_END
