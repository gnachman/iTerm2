//
//  iTermExposeGridView.h
//  iTerm
//
//  Created by George Nachman on 1/19/14.
//
//

#import <Cocoa/Cocoa.h>
#import "iTermExposeTabView.h"

@class PTYTab;

// This is the content view of the exposé window. It shows a gradient in its
// background and may have a bunch of iTermExposeTabViews as children.
@interface iTermExposeGridView : NSView <iTermExposeTabViewDelegate>

// Screen to use for Expose.
+ (NSScreen *)exposeScreen;

- (instancetype)initWithFrame:(NSRect)frame
                       images:(NSArray*)images
                       labels:(NSArray*)labels
                         tabs:(NSArray*)tabs
                       frames:(NSRect*)frames
                 wasMaximized:(NSArray*)wasMaximized
                     putOnTop:(int)topIndex;
- (void)updateTab:(PTYTab*)theTab;
- (void)drawRect:(NSRect)rect;
- (NSRect)tabOrigin:(PTYTab *)theTab visibleScreenFrame:(NSRect)visibleScreenFrame screenFrame:(NSRect)screenFrame;
- (NSSize)zoomedSize:(NSSize)origin thumbSize:(NSSize)thumbSize screenFrame:(NSRect)screenFrame;
- (NSRect)zoomedFrame:(NSRect)dest size:(NSSize)origSize visibleScreenFrame:(NSRect)visibleScreenFrame;
- (iTermExposeTabView*)addTab:(PTYTab *)theTab
                        label:(NSString *)theLabel
                        image:(NSImage *)theImage
                  screenFrame:(NSRect)screenFrame
           visibleScreenFrame:(NSRect)visibleScreenFrame
                        frame:(NSRect)frame
                        index:(int)theIndex
                 wasMaximized:(BOOL)wasMaximized;
// Delegate methods
- (void)onSelection:(iTermExposeTabView*)theView session:(PTYSession*)theSession;
- (BOOL)recomputeIndices;
- (void)setFrames:(NSRect*)frames screenFrame:(NSRect)visibleScreenFrame;
- (void)updateTrackingRectForView:(iTermExposeTabView*)aView;

@end

