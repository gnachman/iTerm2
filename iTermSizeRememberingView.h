//
//  iTermSizeRememberingView.h
//  iTerm
//
//  Created by George Nachman on 6/23/14.
//
//

#import <Cocoa/Cocoa.h>

@interface iTermSizeRememberingView : NSView
@property(nonatomic, readonly) NSSize originalSize;

- (void)resetToOriginalSize;

@end
