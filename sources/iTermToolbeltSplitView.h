//
//  iTermToolbeltSplitView.h
//  iTerm2
//
//  Created by George Nachman on 7/5/15.
//
//

#import <Cocoa/Cocoa.h>

#import "PTYSplitView.h"

// Inherit from PTYSplitView to get its fancy delegate callbacks.
@interface iTermToolbeltSplitView : PTYSplitView

@property (readwrite, copy) NSColor *dividerColor;

@end

