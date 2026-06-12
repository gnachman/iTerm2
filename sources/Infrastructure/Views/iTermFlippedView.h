//
//  iTermFlippedView.h
//  iTerm
//
//  Created by George Nachman on 5/3/14.
//
//

#import <Cocoa/Cocoa.h>

// This is a NSView that returns YES for isFlipped. It's useful for scrollviews
// you create in Interface Builder because only flipped views get their content
// aligned to the top and start with the scroll position at the top. You'll
// need to call -flipSubviews in -awakeFromNib for things to be laid out
// properly.
@interface iTermFlippedView : NSView

- (void)flipSubviews;

@end
