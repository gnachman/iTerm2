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

@interface NSColor (HSP)
@property (nonatomic, readonly) CGFloat it_hspBrightness;
@end

@interface PSMYosemiteTabStyle : NSObject<NSCoding, PSMTabStyle>

@property(nonatomic, readonly) NSColor *tabBarColor;
@property(nonatomic, readonly) PSMTabBarOrientation orientation;

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
@end
