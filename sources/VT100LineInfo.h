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

- (iTermScreenCharAttachmentRunArray *)attachmentRunArray;
- (instancetype)initWithWidth:(int)width;
- (void)setDirty:(BOOL)dirty inRange:(VT100GridRange)range updateTimestamp:(BOOL)updateTimestamp;
- (BOOL)isDirtyAtOffset:(int)x;
- (BOOL)anyCharIsDirty;
- (VT100GridRange)dirtyRange;
- (NSIndexSet *)dirtyIndexes;

- (void)setAttachment:(const iTermScreenCharAttachment *)attachment range:(VT100GridRange)range;

- (iTermScreenCharAttachment *)attachmentAt:(int)x createIfNeeded:(BOOL)createIfNeeded;
- (const iTermScreenCharAttachment *)constAttachmentAt:(int)x;
- (void)setAttachmentRuns:(id<iTermScreenCharAttachmentRunArray>)attachments;
- (id<iTermScreenCharAttachmentsArray>)attachments;
- (iTermMutableScreenCharAttachmentsArray *)mutableAttachmentsCreatingIfNeeded:(BOOL)create;
#warning TOOD: Mutating attachments needs to mark cells dirty
- (void)removeAttachmentAt:(int)x;
- (void)removeAllAttachments;
- (void)copyAttachmentsInRange:(VT100GridRange)range from:(VT100LineInfo *)otherLineInfo;
- (void)copyAttachmentsStartingAtIndex:(int)sourceIndex
                                    to:(int)destIndex
                                 count:(int)count;
- (void)setAttachments:(id<iTermScreenCharAttachmentsArray>)attachments;

@end
