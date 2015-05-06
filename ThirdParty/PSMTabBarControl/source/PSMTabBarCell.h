//
//  PSMTabBarCell.h
//  PSMTabBarControl
//
//  Created by John Pannell on 10/13/05.
//  Copyright 2005 Positive Spin Media. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "PSMTabBarControl.h"
#import "PSMProgressIndicator.h"

@class PSMTabBarControl;
@protocol PSMTabStyle;

@protocol PSMTabBarControlProtocol <NSObject>
- (void)tabClick:(id)sender;
- (id<PSMTabStyle>)style;
- (void)update:(BOOL)animate;
- (BOOL)automaticallyAnimates;
- (PSMTabBarOrientation)orientation;
- (id<PSMTabBarControlDelegate>)delegate;
- (NSTabView *)tabView;
@end

@interface PSMTabBarCell : NSActionCell
// Is this the last cell? Only valid while drawing.
@property(nonatomic, assign) BOOL isLast;
@property(nonatomic, assign) BOOL isCloseButtonSuppressed;
@property(nonatomic, readonly) BOOL closeButtonVisible;

// creation/destruction
- (id)initWithControlView:(PSMTabBarControl *)controlView;
- (id)initPlaceholderWithFrame:(NSRect)frame expanded:(BOOL)value inControlView:(PSMTabBarControl *)controlView;
- (void)dealloc;

// accessors
- (NSTrackingRectTag)closeButtonTrackingTag;
- (void)setCloseButtonTrackingTag:(NSTrackingRectTag)tag;
- (NSTrackingRectTag)cellTrackingTag;
- (void)setCellTrackingTag:(NSTrackingRectTag)tag;
- (float)width;
- (NSRect)frame;
- (void)setFrame:(NSRect)rect;
- (void)setStringValue:(NSString *)aString;
- (NSSize)stringSize;
- (NSAttributedString *)attributedStringValue;
- (int)tabState;
- (void)setTabState:(int)state;
- (PSMProgressIndicator *)indicator;
- (BOOL)isInOverflowMenu;
- (void)setIsInOverflowMenu:(BOOL)value;
- (BOOL)closeButtonPressed;
- (void)setCloseButtonPressed:(BOOL)value;
- (BOOL)closeButtonOver;
- (void)setCloseButtonOver:(BOOL)value;
- (BOOL)hasCloseButton;
- (void)setHasCloseButton:(BOOL)set;
- (BOOL)hasIcon;
- (void)setHasIcon:(BOOL)value;
- (int)count;
- (void)setCount:(int)value;
- (BOOL)isPlaceholder;
- (void)setIsPlaceholder:(BOOL)value;
- (int)currentStep;
- (void)setCurrentStep:(int)value;
- (NSString*)modifierString;
- (void)setModifierString:(NSString*)value;

// component attributes
- (NSRect)indicatorRectForFrame:(NSRect)cellFrame;
- (NSRect)closeButtonRectForFrame:(NSRect)cellFrame;
- (float)minimumWidthOfCell;
- (float)desiredWidthOfCell;

// drawing
- (void)drawWithFrame:(NSRect)cellFrame inView:(NSView *)controlView;

// tracking the mouse
- (void)mouseEntered:(NSEvent *)theEvent;
- (void)mouseExited:(NSEvent *)theEvent;

// drag support
- (NSImage *)dragImage;

// archiving
- (void)encodeWithCoder:(NSCoder *)aCoder;
- (id)initWithCoder:(NSCoder *)aDecoder;

// iTerm add-on
- (NSColor *)tabColor;
- (void)setTabColor:(NSColor *)aColor;
- (void)updateForStyle;
- (void)updateHighlight;

@end

@interface PSMTabBarControl (CellAccessors)

- (id<PSMTabStyle>)style;

@end
