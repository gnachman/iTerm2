//
//  iTermProgressIndicator.h
//  iTerm
//
//  Created by George Nachman on 4/26/14.
//
//

#import <Cocoa/Cocoa.h>

// For some reason, NSProgressIndicator doesn't work well in a menu item view.
// It either flashes or fails to redraw itself.
@interface iTermProgressIndicator : NSView
@property(nonatomic, assign) double fraction;
@end

