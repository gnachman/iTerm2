//
//  iTermExposeTabView.h
//  iTerm
//
//  Created by George Nachman on 1/19/14.
//
//

#import <Cocoa/Cocoa.h>
#import "PTYTab.h"

// This subclass of NSWindow is used for the fullscreen borderless window.
@class iTermExposeTabView;
@class PTYSession;
@class PTYTab;

@protocol iTermExposeTabViewDelegate <NSObject>

- (void)onSelection:(iTermExposeTabView*)theView session:(PTYSession*)theSession;

@end

// This view holds one tab's image and label.
@interface iTermExposeTabView : NSView

@property(nonatomic, readonly) NSRect originalFrame;
@property(nonatomic, nonatomic, retain) NSImage *image;
@property(nonatomic, nonatomic, retain) NSString *label;
@property(nonatomic, assign) id tabObject;
@property(nonatomic, assign) BOOL dirty;
@property(nonatomic, assign) NSRect normalFrame;
@property(nonatomic, assign) NSRect fullSizeFrame;
@property(nonatomic, readonly) int index;
@property(nonatomic, readonly) BOOL wasMaximized;

- (instancetype)initWithImage:(NSImage*)image
                        label:(NSString*)label
                          tab:(PTYTab*)tab
                        frame:(NSRect)frame
                fullSizeFrame:(NSRect)fullSizeFrame
                  normalFrame:(NSRect)normalFrame
                     delegate:(id<iTermExposeTabViewDelegate>)delegate
                        index:(int)theIndex
                 wasMaximized:(BOOL)wasMaximized;

- (NSRect)imageFrame:(NSSize)thumbSize;
- (void)drawRect:(NSRect)rect;
- (void)showLabel;
- (NSTrackingRectTag)trackingRectTag;
- (void)setTrackingRectTag:(NSTrackingRectTag)tag;
- (void)moveToTop;
- (void)bringTabToFore;
- (NSInteger)tabIndex;
- (NSInteger)windowIndex;
- (void)clear;
- (void)setWindowIndex:(int)windowIndex tabIndex:(int)tabIndex;
- (void)setHasResult:(BOOL)hasResult;
- (NSSize)origSize;
- (PTYTab*)tab;
- (void)onMouseExit;
- (void)onMouseEnter;

@end
