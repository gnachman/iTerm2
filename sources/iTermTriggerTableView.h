//
//  iTermTriggerTableView.h
//  iTerm2
//
//  Created by George Nachman on 6/5/15.
//
//

#import <Cocoa/Cocoa.h>
#import "iTermTwoColorWellsCell.h"

// Forwards calls to the iTermTwoColorWellsCellResponder to the delegate.
@interface iTermTriggerTableView : NSTableView<iTermTwoColorWellsCellResponder>
@property(nonatomic, assign) id<NSTableViewDelegate, iTermTwoColorWellsCellResponder> delegate;
@end
