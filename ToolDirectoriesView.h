//
//  ToolDirectoriesView.h
//  iTerm
//
//  Created by George Nachman on 5/1/14.
//
//

#import <Cocoa/Cocoa.h>

@interface ToolDirectoriesView : NSView <
  NSMenuDelegate,
  NSTableViewDataSource,
  NSTableViewDelegate,
  NSTextFieldDelegate>

- (void)updateDirectories;

@end
