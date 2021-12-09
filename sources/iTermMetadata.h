//
//  iTermMetadata.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 9/15/21.
//

#import <Foundation/Foundation.h>
#import "iTermExternalAttributeIndex.h"
#import "VT100GridTypes.h"

NS_ASSUME_NONNULL_BEGIN

typedef struct {
    NSTimeInterval timestamp;
    void * _Nullable externalAttributes;
} iTermMetadata;

typedef struct {
    const NSTimeInterval timestamp;
    const void * _Nullable externalAttributes;
} iTermImmutableMetadata;

NS_INLINE iTermImmutableMetadata iTermMetadataMakeImmutable(iTermMetadata obj) {
    iTermImmutableMetadata result = {
        .timestamp = obj.timestamp,
        .externalAttributes = obj.externalAttributes
    };
    return result;
}

void iTermMetadataInit(iTermMetadata *obj,
                       NSTimeInterval timestamp,
                       iTermExternalAttributeIndex * _Nullable externalAttributes);
iTermMetadata iTermMetadataTemporaryWithTimestamp(NSTimeInterval timestamp);
iTermMetadata iTermMetadataCopy(iTermMetadata obj);
void iTermMetadataRetain(iTermMetadata obj);
void iTermMetadataRelease(iTermMetadata obj);
iTermMetadata iTermMetadataRetainAutorelease(iTermMetadata obj);
iTermMetadata iTermMetadataAutorelease(iTermMetadata obj);

void iTermMetadataReplaceWithCopy(iTermMetadata *obj);

void iTermMetadataSetExternalAttributes(iTermMetadata *obj,
                                        iTermExternalAttributeIndex * _Nullable externalAttributes);

iTermExternalAttributeIndex * _Nullable
iTermMetadataGetExternalAttributesIndex(iTermMetadata obj);

iTermExternalAttributeIndex * _Nullable
iTermMetadataGetExternalAttributesIndexCreatingIfNeeded(iTermMetadata *obj);

id<iTermExternalAttributeIndexReading> _Nullable
iTermImmutableMetadataGetExternalAttributesIndex(iTermImmutableMetadata obj);

void iTermMetadataInitFromArray(iTermMetadata *obj, NSArray *array);
NSArray *iTermMetadataEncodeToArray(iTermMetadata obj);

void iTermMetadataAppend(iTermMetadata *lhs,
                         int lhsLength,
                         iTermMetadata *rhs,
                         int rhsLength);

void iTermMetadataInitCopyingSubrange(iTermMetadata *obj,
                                      iTermMetadata *source,
                                      int start,
                                      int length);

iTermMetadata iTermMetadataDefault(void);

void iTermMetadataReset(iTermMetadata *obj);

NSString *iTermMetadataShortDescription(iTermMetadata metadata, int length);
NSArray * _Nullable iTermMetadataArrayFromData(NSData *data);
NSData *iTermMetadataEncodeToData(iTermMetadata metadata);

NS_ASSUME_NONNULL_END
