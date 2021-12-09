//
//  iTermMetadata.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 9/15/21.
//

#import "iTermMetadata.h"
#import "iTermExternalAttributeIndex.h"
#import "iTermTLVCodec.h"

void iTermMetadataInit(iTermMetadata *obj,
                       NSTimeInterval timestamp,
                       iTermExternalAttributeIndex *externalAttributes) {
    obj->timestamp = timestamp;
    obj->externalAttributes = [(id)externalAttributes retain];
}

iTermMetadata iTermMetadataTemporaryWithTimestamp(NSTimeInterval timestamp) {
    iTermMetadata result;
    iTermMetadataInit(&result, timestamp, nil);
    iTermMetadataAutorelease(result);
    return result;
}

iTermMetadata iTermMetadataCopy(iTermMetadata obj) {
    iTermExternalAttributeIndex *index = [iTermMetadataGetExternalAttributesIndex(obj) copy];
    return (iTermMetadata) {
        .timestamp = obj.timestamp,
        .externalAttributes = index
    };
}

void iTermMetadataRetain(iTermMetadata obj) {
    [(id)obj.externalAttributes retain];
}

void iTermMetadataRelease(iTermMetadata obj) {
    [(id)obj.externalAttributes release];
}

iTermMetadata iTermMetadataRetainAutorelease(iTermMetadata obj) {
    [[(id)obj.externalAttributes retain] autorelease];
    return obj;
}

iTermMetadata iTermMetadataAutorelease(iTermMetadata obj) {
    [(id)obj.externalAttributes autorelease];
    return obj;
}

void iTermMetadataReplaceWithCopy(iTermMetadata *obj) {
    if (!obj->externalAttributes) {
        return;
    }
    iTermExternalAttributeIndex *eaIndex = iTermMetadataGetExternalAttributesIndex(*obj);
    iTermMetadataSetExternalAttributes(obj, [[eaIndex copy] autorelease]);
}

NSArray *iTermMetadataEncodeToArray(iTermMetadata obj) {
    iTermExternalAttributeIndex *eaIndex = iTermMetadataGetExternalAttributesIndex(obj);
    return @[ @(obj.timestamp), [eaIndex dictionaryValue] ?: @{} ];
}

void iTermMetadataSetExternalAttributes(iTermMetadata *obj,
                                        iTermExternalAttributeIndex *externalAttributes) {
    [(id)obj->externalAttributes autorelease];
    obj->externalAttributes = [externalAttributes retain];

}

id<iTermExternalAttributeIndexReading> _Nullable
iTermImmutableMetadataGetExternalAttributesIndex(iTermImmutableMetadata obj) {
    return [[(iTermExternalAttributeIndex *)obj.externalAttributes retain] autorelease];
}

iTermExternalAttributeIndex *iTermMetadataGetExternalAttributesIndex(iTermMetadata obj) {
    return [[(iTermExternalAttributeIndex *)obj.externalAttributes retain] autorelease];
}

iTermExternalAttributeIndex *iTermMetadataGetExternalAttributesIndexCreatingIfNeeded(iTermMetadata *obj) {
    if (!obj->externalAttributes) {
        iTermMetadataSetExternalAttributes(obj, [[[iTermExternalAttributeIndex alloc] init] autorelease]);
    }
    return [[(iTermExternalAttributeIndex *)obj->externalAttributes retain] autorelease];
}

void iTermMetadataInitFromArray(iTermMetadata *obj, NSArray *array) {
    if (array.count < 2) {
        iTermMetadataInit(obj, 0, nil);
        return;
    }
    iTermMetadataInit(obj,
                      [array[0] doubleValue],
                      [[[iTermExternalAttributeIndex alloc] initWithDictionary:array[1]] autorelease]);
}

void iTermMetadataAppend(iTermMetadata *lhs,
                         int lhsLength,
                         iTermMetadata *rhs,
                         int rhsLength) {
    lhs->timestamp = rhs->timestamp;
    if (!rhs->externalAttributes) {
        return;
    }
    iTermExternalAttributeIndex *lhsAttrs = iTermMetadataGetExternalAttributesIndexCreatingIfNeeded(lhs);
    iTermExternalAttributeIndex *eaIndex =
        [iTermExternalAttributeIndex concatenationOf:lhsAttrs
                                              length:lhsLength
                                                with:iTermMetadataGetExternalAttributesIndex(*rhs)
                                              length:rhsLength];
    iTermMetadataSetExternalAttributes(lhs, eaIndex);
}

void iTermMetadataInitByConcatenation(iTermMetadata *obj,
                                      iTermMetadata *lhs,
                                      int lhsLength,
                                      iTermMetadata *rhs,
                                      int rhsLength) {
    iTermExternalAttributeIndex *eaIndex =
        [iTermExternalAttributeIndex concatenationOf:iTermMetadataGetExternalAttributesIndex(*lhs)
                                              length:lhsLength
                                                with:iTermMetadataGetExternalAttributesIndex(*rhs)
                                          length:rhsLength];
    iTermMetadataInit(obj, rhs->timestamp, eaIndex);
}

void iTermMetadataInitCopyingSubrange(iTermMetadata *obj,
                                      iTermMetadata *source,
                                      int start,
                                      int length) {
    iTermExternalAttributeIndex *sourceIndex = iTermMetadataGetExternalAttributesIndex(*source);
    iTermExternalAttributeIndex *eaIndex = [sourceIndex subAttributesFromIndex:start maximumLength:length];
    iTermMetadataInit(obj,
                      source->timestamp,
                      eaIndex);
}

iTermMetadata iTermMetadataDefault(void) {
    return (iTermMetadata){ .timestamp = 0, .externalAttributes = NULL };
}

void iTermMetadataReset(iTermMetadata *obj) {
    obj->timestamp = 0;
    iTermMetadataSetExternalAttributes(obj, NULL);
}

NSString *iTermMetadataShortDescription(iTermMetadata metadata, int length) {
    return [NSString stringWithFormat:@"<iTermMetadata timestamp=%@ ea=%@>", @(metadata.timestamp), iTermMetadataGetExternalAttributesIndex(metadata)];
}

NSArray *iTermMetadataArrayFromData(NSData *data) {
    iTermMetadata temp;
    memset(&temp, 0, sizeof(temp));
    iTermTLVDecoder *decoder = [[[iTermTLVDecoder alloc] initWithData:data] autorelease];
    if (![decoder decodeDouble:&temp.timestamp]) {
        return nil;
    }
    NSData *attrData = [decoder decodeData];
    if (!attrData) {
        return nil;
    }
    iTermExternalAttributeIndex *attr = [iTermExternalAttributeIndex fromData:attrData];
    iTermMetadataSetExternalAttributes(&temp, attr);
    NSArray *result = iTermMetadataEncodeToArray(temp);
    iTermMetadataRelease(temp);
    return result;
}

NSData *iTermMetadataEncodeToData(iTermMetadata metadata) {
    iTermTLVEncoder *encoder = [[[iTermTLVEncoder alloc] init] autorelease];
    [encoder encodeDouble:metadata.timestamp];
    iTermExternalAttributeIndex *attr = iTermMetadataGetExternalAttributesIndex(metadata);
    [encoder encodeData:[attr data] ?: [NSData data]];
    return encoder.data;
}
