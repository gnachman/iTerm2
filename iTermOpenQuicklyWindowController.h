//
//  iTermOpenQuicklyWindowController.h
//  iTerm
//
//  Created by George Nachman on 7/10/14.
//
//

#import <Cocoa/Cocoa.h>

@interface iTermOpenQuicklyWindow : NSPanel
@end

@interface iTermOpenQuicklyWindowController : NSWindowController

+ (instancetype)sharedInstance;
- (void)presentWindow;

@end
