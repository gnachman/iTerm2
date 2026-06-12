//
//  iTermToolSnippets.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 8/14/20.
//

#import <Cocoa/Cocoa.h>

#import "FutureMethods.h"
#import "iTermToolbeltView.h"

NS_ASSUME_NONNULL_BEGIN

@interface iTermToolSnippets : NSView <ToolbeltTool, NSTableViewDataSource, NSTableViewDelegate>

- (void)currentSessionDidChange;

@end

NS_ASSUME_NONNULL_END
