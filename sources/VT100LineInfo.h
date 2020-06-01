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
- (iTermScreenCharAttachment *)attachmentAt:(int)x createIfNeeded:(BOOL)createIfNeeded;
- (const iTermScreenCharAttachment *)constAttachmentAt:(int)x;
- (void)setAttachmentRuns:(id<iTermScreenCharAttachmentRunArray>)attachments;
- (id<iTermScreenCharAttachmentsArray>)attachments;
- (void)removeAttachmentAt:(int)x;

@end
