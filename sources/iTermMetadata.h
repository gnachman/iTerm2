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

// I'd like to make these const to keep users well-behaved but C++ makes structs with const fields
// practically unsuable becase of implicitly deleted operators.
//
// Note also that "immutable" here means that the code holding this object cannot change it, but
// that doesn't prevent the externalAttributes from being mutated elsewhere.
// This follows the NSArray/NSMutableArray model. When you get this, you should make a copy of it
// if you really care about it not changing out from under you.
typedef struct {
    NSTimeInterval timestamp;
    void * _Nullable externalAttributes;
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

void iTermImmutableMetadataInit(iTermImmutableMetadata *obj,
                                NSTimeInterval timestamp,
                                id<iTermExternalAttributeIndexReading> _Nullable externalAttributes);

iTermMetadata iTermMetadataTemporaryWithTimestamp(NSTimeInterval timestamp);
iTermMetadata iTermMetadataCopy(iTermMetadata obj);
iTermMetadata iTermImmutableMetadataMutableCopy(iTermImmutableMetadata obj);
iTermImmutableMetadata iTermImmutableMetadataCopy(iTermImmutableMetadata obj);

void iTermMetadataRetain(iTermMetadata obj);
void iTermMetadataRelease(iTermMetadata obj);
iTermMetadata iTermMetadataRetainAutorelease(iTermMetadata obj);
iTermMetadata iTermMetadataAutorelease(iTermMetadata obj);

void iTermImmutableMetadataRetain(iTermImmutableMetadata obj);
void iTermImmutableMetadataRelease(iTermImmutableMetadata obj);
iTermImmutableMetadata iTermImmutableMetadataRetainAutorelease(iTermImmutableMetadata obj);
iTermImmutableMetadata iTermImmutableMetadataAutorelease(iTermImmutableMetadata obj);

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
NSArray *iTermImmutableMetadataEncodeToArray(iTermImmutableMetadata obj);
NSArray *iTermMetadataEncodeToArray(iTermMetadata obj);

void iTermMetadataAppend(iTermMetadata *lhs,
                         int lhsLength,
                         iTermImmutableMetadata *rhs,
                         int rhsLength);

void iTermMetadataInitCopyingSubrange(iTermMetadata *obj,
                                      iTermImmutableMetadata *source,
                                      int start,
                                      int length);

iTermMetadata iTermMetadataDefault(void);
iTermImmutableMetadata iTermImmutableMetadataDefault(void);

void iTermMetadataReset(iTermMetadata *obj);

NSString *iTermMetadataShortDescription(iTermMetadata metadata, int length);
NSArray * _Nullable iTermMetadataArrayFromData(NSData *data);
NSData *iTermMetadataEncodeToData(iTermMetadata metadata);

NS_ASSUME_NONNULL_END
