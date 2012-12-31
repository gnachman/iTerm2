//
//  SharedCharacterRunData.h
//  iTerm
//
//  Created by George Nachman on 12/31/12.
//
//

#import <Foundation/Foundation.h>

@interface SharedCharacterRunData : NSObject {
    int capacity_;  // Allocated entries in codes, advances, glyphs arrays.
    __weak unichar *codes_;
    __weak CGSize *advances_;
    __weak CGGlyph *glyphs_;
    NSRange freeRange_;
}

+ (SharedCharacterRunData *)sharedCharacterRunDataWithCapacity:(int)capacity;

#pragma mark Modify allocated range

- (void)growAllocation:(NSRange *)allocation by:(int)growBy;
- (void)advanceAllocation:(NSRange *)allocation by:(int)advanceBy;
- (void)truncateAllocation:(NSRange *)allocation toSize:(int)newSize;

#pragma mark Access values in allocated range

- (unichar *)codesInRange:(NSRange)allocation;
- (CGSize *)advancesInRange:(NSRange)allocation;
- (CGGlyph *)glyphsInRange:(NSRange)allocation;

@end
