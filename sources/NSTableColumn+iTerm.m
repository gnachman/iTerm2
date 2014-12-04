//
//  NSTableView_iTerm.m
//  iTerm2
//
//  Created by George Nachman on 12/2/14.
//
//

#import "NSTableColumn+iTerm.h"

@implementation NSTableColumn (iTerm)

- (CGFloat)suggestedRowHeight {
  NSCell *cell = [self dataCell];
  NSRect constrainedBounds = NSMakeRect(0, 0, self.width, CGFLOAT_MAX);
  return [cell cellSizeForBounds:constrainedBounds].height;
}


@end
