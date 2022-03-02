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

extern BOOL gDebugLogging;
int DebugLogImpl(const char *file, int line, const char *function, NSString* value);
#define DLog(args...) \
    do { \
        if (gDebugLogging) { \
            DebugLogImpl(__FILE__, __LINE__, __FUNCTION__, [NSString stringWithFormat:args]); \
        } \
    } while (0)

@interface NSColor (HSP)
@property (nonatomic, readonly) CGFloat it_hspBrightness;
@end

@interface PSMYosemiteTabStyle : NSObject<NSCoding, PSMTabStyle>

@property(nonatomic, readonly) NSColor *tabBarColor;
@property(nonatomic, readonly) PSMTabBarOrientation orientation;
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
                                                 window:(NSWindow *)window;
- (void)drawCellBackgroundSelected:(BOOL)selected
                            inRect:(NSRect)cellFrame
                      withTabColor:(NSColor *)tabColor
                   highlightAmount:(CGFloat)highlightAmount
                        horizontal:(BOOL)horizontal;
- (void)drawShadowForUnselectedTabInRect:(NSRect)backgroundRect;

- (void)drawSubtitle:(PSMCachedTitle *)cachedSubtitle
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
                   cachedTitle:(PSMCachedTitle *)cachedTitle
                 reservedSpace:(CGFloat)reservedSpace
                  boundingSize:(NSSize *)boundingSizeOut
                      truncate:(BOOL *)truncateOut;

- (BOOL)willDrawSubtitle:(PSMCachedTitle *)subtitle;
- (CGFloat)verticalOffsetForTitleWhenSubtitlePresent;
- (CGFloat)verticalOffsetForSubtitle;

- (BOOL)shouldDrawTopLineSelected:(BOOL)selected
                         attached:(BOOL)attached
                         position:(PSMTabPosition)position NS_AVAILABLE_MAC(10_16);

@end
