//
//  iTermTwoColorWellsCell.h
//  iTerm2
//
//  Created by George Nachman on 6/5/15.
//
//

#import <Cocoa/Cocoa.h>

// First responders can implement these methods to find out about what the cell is doing.
@protocol iTermTwoColorWellsCellResponder <NSObject>

@optional
- (void)twoColorWellsCellDidOpenPickerForWellNumber:(int)wellNumber;
- (NSNumber *)currentWellForCell;

@end


@interface iTermTwoColorWellsCell : NSCell
@property(nonatomic, retain) NSColor *textColor;
@property(nonatomic, retain) NSColor *backgroundColor;
@end

