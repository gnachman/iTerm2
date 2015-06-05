//
//  iTermTriggerTableView.m
//  iTerm2
//
//  Created by George Nachman on 6/5/15.
//
//

#import "iTermTriggerTableView.h"

@implementation iTermTriggerTableView

@dynamic delegate;

- (void)twoColorWellsCellDidOpenPickerForWellNumber:(int)wellNumber {
  if ([self.delegate respondsToSelector:@selector(twoColorWellsCellDidOpenPickerForWellNumber:)]) {
    [_delegate twoColorWellsCellDidOpenPickerForWellNumber:wellNumber];
  }
}

- (NSNumber *)currentWellForCell {
  if ([self.delegate respondsToSelector:@selector(currentWellForCell)]) {
    return [(id)_delegate currentWellForCell];
  } else {
    return nil;
  }
}

@end
