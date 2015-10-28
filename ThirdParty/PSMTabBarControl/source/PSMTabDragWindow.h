//
//  PSMTabDragWindow.h
//  PSMTabBarControl
//
//  Created by Kent Sutherland on 6/1/06.
//  Copyright 2006 Kent Sutherland. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@class PSMTabBarCell;

@interface PSMTabDragWindow : NSWindow

@property(nonatomic, readonly) NSImage *image;

+ (PSMTabDragWindow *)dragWindowWithTabBarCell:(PSMTabBarCell *)cell
                                         image:(NSImage *)image
                                     styleMask:(unsigned int)styleMask;

- (instancetype)initWithTabBarCell:(PSMTabBarCell *)cell
                             image:(NSImage *)image
                         styleMask:(unsigned int)styleMask;

- (void)fadeToAlpha:(CGFloat)alpha
           duration:(NSTimeInterval)duration
         completion:(void (^)())completion;
- (void)setImageOpacity:(CGFloat)alpha;

@end
