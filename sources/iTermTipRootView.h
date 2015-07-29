//
//  iTermWelcomeRootView.h
//  iTerm2
//
//  Created by George Nachman on 6/16/15.
//
//

#import <Cocoa/Cocoa.h>

// Root view for the tip window. Draws transparent. Is not layer backed because
// a window's content view can't be both transparent and layer-backed.
@interface iTermTipRootView : NSView

@end
