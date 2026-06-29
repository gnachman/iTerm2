//
//  ToolCapturedOutput.h
//  iTerm
//
//  Created by George Nachman on 5/22/14.
//
//

#import <Cocoa/Cocoa.h>

@interface ToolCapturedOutputView : NSView<
    NSTableViewDataSource,
    NSTableViewDelegate>

// Exposed for testing only.
@property(nonatomic, readonly) NSTableView *tableView;

- (void)updateCapturedOutput;
- (void)removeSelection;

@end
