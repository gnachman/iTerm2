//
//  VT100LineInfo.h
//  iTerm
//
//  Created by George Nachman on 11/17/13.
//
//

#import <Foundation/Foundation.h>

#import "ScreenChar.h"
#import "VT100GridTypes.h"

@interface VT100LineInfo : NSObject <NSCopying>

@property(nonatomic, assign) NSTimeInterval timestamp;
@property(nonatomic, readonly) NSInteger generation;
@property(nonatomic, readonly) iTermMutableScreenCharAttachmentsArray *attachments;
@property(nullable, nonatomic, readonly) iTermMutableScreenCharAttachmentsArray *maybeAttachments;
@property(nonatomic, readonly) BOOL hasAttachments;
// When set to YES, updates timestamp.
@property(nonatomic, getter=isDirty) BOOL dirty;

- (instancetype)initWithWidth:(int)width;

- (void)setAttachments:(id<iTermScreenCharAttachmentsArray>)attachments;
- (void)markDirtyWithoutUpdatingTimestamp;

@end
