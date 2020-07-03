//
//  iTermScreenCharAttachment.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 5/31/20.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(unsigned int, iTermUnderlineColorMode) {
    iTermUnderlineColorModeNone = 0,
    iTermUnderlineColorMode256 = 1,
    iTermUnderlineColorMode24bit = 2
};

typedef struct {
    unsigned int underlineRed : 8;  // gives color code is mode is 256
    unsigned int underlineGreen : 8;  // unused unless mode is 24bit
    unsigned int underlineBlue : 8;  // unused unless mode is 24bit
    iTermUnderlineColorMode underlineColorMode : 2;

    unsigned int unusedBits: 6;
    unsigned char unusedBytes[12];
} iTermScreenCharAttachment;

typedef struct {
    unsigned int offset;
    unsigned int length;
    iTermScreenCharAttachment attachment;
} iTermScreenCharAttachmentRun;

@protocol iTermScreenCharAttachmentsArray;
@class iTermScreenCharAttachmentRunArray;

@protocol iTermScreenCharAttachmentRunArray<NSObject>
@property (nonatomic, readonly) const iTermScreenCharAttachmentRun *runs;
@property (nonatomic, readonly) NSUInteger count;
@property (nonatomic, readonly) NSData *serialized;

- (id<iTermScreenCharAttachmentRunArray>)appending:(id<iTermScreenCharAttachmentRunArray>)suffix
                                      addingOffset:(int)offset;
- (id<iTermScreenCharAttachmentRunArray>)runArrayByAddingOffset:(int)offset;
- (id<iTermScreenCharAttachmentRunArray>)runsInRange:(NSRange)range
                                        addingOffset:(int)offset;
- (id<iTermScreenCharAttachmentRunArray>)copy;
- (id<iTermScreenCharAttachmentsArray>)attachmentsArrayOfLength:(int)width;
@end

@protocol iTermScreenCharAttachmentsArray<NSCopying, NSObject>
@property (nonatomic, readonly) NSIndexSet *validAttachments;
@property (nonatomic, readonly) const iTermScreenCharAttachment *attachments;
@property (nonatomic, readonly) NSUInteger count;
@property (nonatomic, readonly) id<iTermScreenCharAttachmentRunArray> runArray;

- (BOOL)isEqual:(id)object;
- (const iTermScreenCharAttachment *)attachmentAtIndex:(int)index;
@end

@interface iTermScreenCharAttachmentsRunArrayBuilder: NSObject
@property (nonatomic, readonly) id <iTermScreenCharAttachmentRunArray>runArray;

- (void)appendRun:(const iTermScreenCharAttachmentRun *)run;
- (void)appendRuns:(const iTermScreenCharAttachmentRun *)run
             count:(NSUInteger)count
      addingOffset:(int)offset;

@end

#pragma mark - iTermScreenCharAttachmentRunArray

@interface iTermScreenCharAttachmentRunArray: NSObject<NSCopying, iTermScreenCharAttachmentRunArray>

+ (instancetype)runArrayWithRuns:(const iTermScreenCharAttachmentRun *)runs
                           count:(int)count;
- (instancetype)initWithSerialized:(NSData *)serialized;
;
@end

#pragma mark - iTermScreenCharAttachmentsArray

@interface iTermScreenCharAttachmentsArray: NSObject<iTermScreenCharAttachmentsArray, NSCopying>

- (instancetype)initWithValidAttachmentIndexes:(NSIndexSet *)validAttachments
                                   attachments:(const iTermScreenCharAttachment *)attachments
                                         count:(NSUInteger)count;

- (instancetype)initWithRepeatedAttachment:(const iTermScreenCharAttachment *)attachment
                                     count:(NSUInteger)count;

- (instancetype)init NS_UNAVAILABLE;
@end

#pragma mark - iTermMutableScreenCharAttachmentsArray

@interface iTermMutableScreenCharAttachmentsArray: NSObject<iTermScreenCharAttachmentsArray, NSCopying>
@property (nonatomic, readonly) NSMutableIndexSet *mutableValidAttachments;
@property (nonatomic, readonly) iTermScreenCharAttachment *mutableAttachments;
@property (nonatomic, readonly) NSUInteger count;
@property (nonatomic, readonly) NSUInteger generation;
@property (nonatomic) BOOL dirty;
@property (nullable, nonatomic, readonly) id<iTermScreenCharAttachmentRunArray> runArray;

- (instancetype)initWithCount:(NSUInteger)count NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
- (instancetype)mutableCopy;
- (void)copyAttachmentsInRange:(NSRange)range from:(id<iTermScreenCharAttachmentsArray>)other;
- (void)copyAttachmentsStartingAtIndex:(int)sourceIndex
                                    to:(int)destIndex
                                 count:(int)count;
- (void)removeAttachmentsInRange:(NSRange)range;
- (void)removeAllAttachments;
- (void)setAttachment:(const iTermScreenCharAttachment * _Nullable)attachment
              inRange:(NSRange)range;
- (void)copyAttachmentsFromArray:(id<iTermScreenCharAttachmentsArray>)sourceArray
                      fromOffset:(int)sourceOffset
                        toOffset:(int)destOffset
                           count:(int)count;
- (void)setFromRuns:(id<iTermScreenCharAttachmentRunArray>)attachments;
@end

NS_ASSUME_NONNULL_END
