//
//  iTermBackgroundDrawingHelper.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 8/5/18.
//

#import <Cocoa/Cocoa.h>

#import "ITAddressBookMgr.h"

@class SessionView;

@protocol iTermBackgroundDrawingHelperDelegate<NSObject>
- (SessionView *)backgroundDrawingHelperView;  // _view
- (NSImage *)backgroundDrawingHelperImage;  // _backgroundImage
- (BOOL)backgroundDrawingHelperUseTransparency;  // _textview.useTransparency
- (CGFloat)backgroundDrawingHelperTransparency;  // _textview.transparency
- (iTermBackgroundImageMode)backgroundDrawingHelperBackgroundImageMode;  // _backgroundImageMode
- (NSColor *)backgroundDrawingHelperDefaultBackgroundColor;  // [self processedBackgroundColor];
- (CGFloat)backgroundDrawingHelperBlending;  // _textview.blend
@end

@interface iTermBackgroundDrawingHelper : NSObject
@property (nonatomic, weak) id<iTermBackgroundDrawingHelperDelegate> delegate;

- (void)drawBackgroundImageInView:(NSView *)view
                         viewRect:(NSRect)rect
           blendDefaultBackground:(BOOL)blendDefaultBackground;

@end
