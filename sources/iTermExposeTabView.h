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
{
    NSImage* image_;
    NSString* label_;
    NSInteger tabIndex_;
    NSInteger windowIndex_;
    BOOL showLabel_;
    NSRect originalFrame_;
    NSRect fullSizeFrame_;
    NSRect normalFrame_;
    NSTrackingRectTag trackingRectTag_;
    BOOL highlight_;
    id tabObject_;
    id<iTermExposeTabViewDelegate> delegate_;
    BOOL dirty_;
    BOOL hasResult_;
    NSSize origSize_;
    int index_;
    BOOL wasMaximized_;
}

- (id)initWithImage:(NSImage*)image
              label:(NSString*)label
                tab:(PTYTab*)tab
              frame:(NSRect)frame
      fullSizeFrame:(NSRect)fullSizeFrame
        normalFrame:(NSRect)normalFrame
           delegate:(id<iTermExposeTabViewDelegate>)delegate
              index:(int)theIndex
       wasMaximized:(BOOL)wasMaximized;

- (void)dealloc;
- (NSRect)imageFrame:(NSSize)thumbSize;
- (NSRect)originalFrame;
- (void)drawRect:(NSRect)rect;
- (void)showLabel;
- (NSTrackingRectTag)trackingRectTag;
- (void)setTrackingRectTag:(NSTrackingRectTag)tag;
- (void)moveToTop;
- (void)bringTabToFore;
- (NSInteger)tabIndex;
- (NSInteger)windowIndex;
- (void)setImage:(NSImage*)newImage;
- (void)setLabel:(NSString*)newLabel;
- (NSString*)label;
- (void)setTabObject:(id)tab;
- (id)tabObject;
- (void)clear;
- (void)setDirty:(BOOL)dirty;
- (BOOL)dirty;
- (void)setWindowIndex:(int)windowIndex tabIndex:(int)tabIndex;
- (void)setHasResult:(BOOL)hasResult;
- (NSImage*)image;
- (void)setNormalFrame:(NSRect)normalFrame;
- (NSRect)normalFrame;
- (void)setFullSizeFrame:(NSRect)fullSizeFrame;
- (NSSize)origSize;
- (int)index;
- (PTYTab*)tab;
- (BOOL)wasMaximized;
- (void)onMouseExit;
- (void)onMouseEnter;

@end
