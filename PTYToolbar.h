//
//  PTYToolbar.h
//  iTerm
//
//  Created by George Nachman on 3/18/13.
//
//

#import <Cocoa/Cocoa.h>

@protocol PTYToolbarDelegate <NSToolbarDelegate, NSObject>

@optional
- (void)toolbarDidChangeVisibility:(PTYToolbar *)toolbar;

@end

@interface PTYToolbar : NSToolbar

- (void)setDelegate:(id<PTYToolbarDelegate>)delegate;

@end
