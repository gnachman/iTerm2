//
//  iTermBottomMarginView.h
//  iTerm2
//
//  Created by George Nachman on 11/16/16.
//
//

#import <Cocoa/Cocoa.h>

@interface iTermBottomMarginView : NSView

@property(nonatomic, copy) void (^drawRect)(NSRect);

@end
