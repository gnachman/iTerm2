//
//  iTermMetalClipView.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 10/2/17.
//

#import <Cocoa/Cocoa.h>

@class MTKView;

@interface iTermMetalClipView : NSClipView

@property (nonatomic, weak) MTKView *metalView;

@end
