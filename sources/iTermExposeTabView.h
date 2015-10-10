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
@property (readonly) NSRect originalFrame;
- (void)drawRect:(NSRect)rect;
- (void)showLabel;
- (NSTrackingRectTag)trackingRectTag;
- (void)setTrackingRectTag:(NSTrackingRectTag)tag;
- (void)moveToTop;
- (void)bringTabToFore;
- (NSInteger)tabIndex;
- (NSInteger)windowIndex;
@property (nonatomic, retain) NSImage *image;
@property (nonatomic, retain) NSString *label;
@property (assign) id tabObject;
- (void)clear;
@property BOOL dirty;
- (void)setWindowIndex:(int)windowIndex tabIndex:(int)tabIndex;
- (void)setHasResult:(BOOL)hasResult;
@property NSRect normalFrame;
@property NSRect fullSizeFrame;
- (NSSize)origSize;
@property (readonly) int index;
- (PTYTab*)tab;
@property (readonly) BOOL wasMaximized;
- (void)onMouseExit;
- (void)onMouseEnter;

@end
