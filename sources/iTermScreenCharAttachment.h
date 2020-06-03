//
//  iTermScreenCharAttachment.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 5/31/20.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef struct {
    unsigned int underlineRed : 8;
    unsigned int underlineGreen : 8;
    unsigned int underlineBlue : 8;
    unsigned int hasUnderlineColor: 1;

    unsigned int unusedBits: 6;
    unsigned int valid: 1;
    unsigned char unusedBytes[12];
} iTermScreenCharAttachment;

typedef struct {
    unsigned short offset;
    unsigned short length;
    iTermScreenCharAttachment attachment;
} iTermScreenCharAttachmentRun;

@class iTermScreenCharAttachmentRunArray;
@class iTermScreenCharAttachmentRunArraySlice;

@protocol iTermScreenCharAttachmentRunArray<NSObject>
@property (nonatomic, readonly) const iTermScreenCharAttachmentRun *runs;
@property (nonatomic, readonly) NSUInteger count;
@property (nonatomic, readonly) int baseOffset;

- (iTermScreenCharAttachmentRunArray *)makeRunArray;
@end

@protocol iTermScreenCharAttachmentsArray<NSObject>
@property (nonatomic, readonly) NSIndexSet *validAttachments;
@property (nonatomic, readonly) const iTermScreenCharAttachment *attachments;
@property (nonatomic, readonly) NSUInteger count;
@property (nonatomic, readonly) id<iTermScreenCharAttachmentRunArray> runArray;

- (BOOL)isEqual:(id)object;
@end

#pragma mark - iTermScreenCharAttachmentRunArray

@interface iTermScreenCharAttachmentRunArray: NSObject<NSCopying, iTermScreenCharAttachmentRunArray>
@property (nonatomic) int baseOffset;
@property (nonatomic, readonly) NSData *serialized;

+ (instancetype)runArrayWithRuns:(iTermScreenCharAttachmentRun *)runs
                           count:(int)count;
- (instancetype)initWithSerialized:(NSData *)serialized;

- (void)append:(id<iTermScreenCharAttachmentRunArray>)other baseOffset:(int)baseOffset;
- (iTermScreenCharAttachmentRunArraySlice *)sliceFrom:(int)offset length:(int)sliceLength;
- (iTermScreenCharAttachmentRunArraySlice *)asSlice;

// Doesn't actually free memory because there might be slices referring to the truncated portion.
- (void)truncateFrom:(int)offset;
@end

#pragma mark - iTermScreenCharAttachmentRunArraySlice

@interface iTermScreenCharAttachmentRunArraySlice: NSObject<iTermScreenCharAttachmentRunArray>
@property (nonatomic, strong, readonly) iTermScreenCharAttachmentRunArray *realArray;
@property (nonatomic, readonly) int baseOffset;
@property (nonatomic, readonly) id<iTermScreenCharAttachmentsArray> fullArray;

- (instancetype)initWithRunArray:(iTermScreenCharAttachmentRunArray *)runArray
                           range:(NSRange)range NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
@end

#pragma mark - iTermScreenCharAttachmentsArray

@interface iTermScreenCharAttachmentsArray: NSObject<iTermScreenCharAttachmentsArray, NSCopying>

- (instancetype)initWithValidAttachmentIndexes:(NSIndexSet *)validAttachments
                                   attachments:(const iTermScreenCharAttachment *)attachments
                                         count:(NSUInteger)count NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
@end

#pragma mark - iTermMutableScreenCharAttachmentsArray

@interface iTermMutableScreenCharAttachmentsArray: NSObject<iTermScreenCharAttachmentsArray, NSCopying>
@property (nonatomic, readonly) NSMutableIndexSet *mutableValidAttachments;
@property (nonatomic, readonly) iTermScreenCharAttachment *mutableAttachments;
@property (nonatomic, readonly) NSUInteger count;

- (instancetype)initWithCount:(NSUInteger)count NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
- (instancetype)mutableCopy;
@end

NS_ASSUME_NONNULL_END
