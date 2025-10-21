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
#define DLog(args...) \
    do { \
        if (gDebugLogging) { \
            DebugLogImpl(__FILE__, __LINE__, __FUNCTION__, [NSString stringWithFormat:args]); \
        } \
    } while (0)

// __cyclicLog should be an instance of iTermCyclicLog
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
- (CGFloat)tabColorBrightness:(PSMTabBarCell *)cell;
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
