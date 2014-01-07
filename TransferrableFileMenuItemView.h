//
//  TransferrableFileMenuItemView.h
//  iTerm
//
//  Created by George Nachman on 12/23/13.
//
//

#import <Cocoa/Cocoa.h>

// For some reason, NSProgressIndicator doesn't work well in a menu item view.
// It either flashes or fails to redraw itself.
@interface iTermProgressIndicator : NSView
@property(nonatomic, assign) double fraction;
@end

@interface TransferrableFileMenuItemView : NSView

@property(nonatomic, copy) NSString *filename;
@property(nonatomic, copy) NSString *subheading;
@property(nonatomic, assign) long long size;
@property(nonatomic, assign) long long bytesTransferred;
@property(nonatomic, copy) NSString *statusMessage;
@property(nonatomic, retain) iTermProgressIndicator *progressIndicator;
@property(nonatomic, assign) BOOL lastDrawnHighlighted;

@end
