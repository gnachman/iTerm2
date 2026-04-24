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
                       BOOL rtlFound,
                       iTermExternalAttributeIndex *externalAttributes,
                       iTermLineAttribute lineAttribute) {
    obj->timestamp = timestamp;
    obj->rtlFound = rtlFound;
    obj->lineAttribute = lineAttribute;
    obj->externalAttributes = [(id)externalAttributes retain];
}

void iTermImmutableMetadataInit(iTermImmutableMetadata *obj,
                                NSTimeInterval timestamp,
                                BOOL rtlFound,
                                id<iTermExternalAttributeIndexReading> _Nullable externalAttributes,
                                iTermLineAttribute lineAttribute) {
    iTermMetadataInit((iTermMetadata *)obj,
                      timestamp,
                      rtlFound,
                      (iTermExternalAttributeIndex *)externalAttributes,
                      lineAttribute);
}

iTermMetadata iTermMetadataTemporaryWithTimestamp(NSTimeInterval timestamp) {
    iTermMetadata result;
    iTermMetadataInit(&result, timestamp, NO, nil, iTermLineAttributeSingleWidth);
    iTermMetadataAutorelease(result);
    return result;
}

iTermMetadata iTermMetadataCopy(iTermMetadata obj) {
    // The analyzer says this is a leak but I really don't think it is.
    return iTermImmutableMetadataMutableCopy(iTermMetadataMakeImmutable(obj));
}

iTermMetadata iTermImmutableMetadataMutableCopy(iTermImmutableMetadata obj) {
    iTermExternalAttributeIndex *index = obj.externalAttributes ? [iTermImmutableMetadataGetExternalAttributesIndex(obj) mutableCopyWithZone:nil] : nil;
    return (iTermMetadata) {
        .timestamp = obj.timestamp,
        .rtlFound = obj.rtlFound,
        .externalAttributes = index,
        .lineAttribute = obj.lineAttribute
    };
}

iTermImmutableMetadata iTermImmutableMetadataCopy(iTermImmutableMetadata obj) {
    return iTermMetadataMakeImmutable(iTermImmutableMetadataMutableCopy(obj));
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

void iTermImmutableMetadataRetain(iTermImmutableMetadata obj) {
    [(id)obj.externalAttributes retain];
}

void iTermImmutableMetadataRelease(iTermImmutableMetadata obj) {
    [(id)obj.externalAttributes release];
}

iTermImmutableMetadata iTermImmutableMetadataRetainAutorelease(iTermImmutableMetadata obj) {
    [[(id)obj.externalAttributes retain] autorelease];
    return obj;
}

iTermImmutableMetadata iTermImmutableMetadataAutorelease(iTermImmutableMetadata obj) {
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

NSArray *iTermImmutableMetadataEncodeToArray(iTermImmutableMetadata obj) {
    iTermExternalAttributeIndex *eaIndex = iTermImmutableMetadataGetExternalAttributesIndex(obj);
    // NOTE: None of these may be arrays.
    return @[ @(obj.timestamp),
              [eaIndex dictionaryValue] ?: @{},
              @(obj.rtlFound),
              @(obj.lineAttribute) ];
}

NSArray *iTermMetadataEncodeToArray(iTermMetadata obj) {
    return iTermImmutableMetadataEncodeToArray(iTermMetadataMakeImmutable(obj));
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

void iTermImmutableMetadataDeriveLineAttributeFromExternalAttributes(iTermImmutableMetadata *metadata) {
    id<iTermExternalAttributeIndexReading> eaIndex =
        iTermImmutableMetadataGetExternalAttributesIndex(*metadata);
    if (!eaIndex) {
        return;
    }
    const iTermLineAttribute derivedAttr = [eaIndex uniformLineAttribute];
    if (derivedAttr != iTermLineAttributeSingleWidth) {
        ((iTermMetadata *)metadata)->lineAttribute = derivedAttr;
    }
}

void iTermMetadataInitFromArray(iTermMetadata *obj, NSArray *array) {
    if (array.count < 2) {
        iTermMetadataInit(obj, 0, NO, nil, iTermLineAttributeSingleWidth);
        return;
    }
    const iTermLineAttribute lineAttr = (array.count >= 4)
        ? (iTermLineAttribute)[array[3] unsignedCharValue]
        : iTermLineAttributeSingleWidth;
    if (array.count < 3) {
        iTermMetadataInit(obj,
                          [array[0] doubleValue],
                          NO,
                          [[[iTermExternalAttributeIndex alloc] initWithDictionary:array[1]] autorelease],
                          lineAttr);
        return;
    }
    iTermMetadataInit(obj,
                      [array[0] doubleValue],
                      [array[2] boolValue],
                      [[[iTermExternalAttributeIndex alloc] initWithDictionary:array[1]] autorelease],
                      lineAttr);
}

void iTermMetadataAppend(iTermMetadata *lhs,
                         int lhsLength,
                         const iTermImmutableMetadata *rhs,
                         int rhsLength) {
    lhs->timestamp = rhs->timestamp;
    lhs->rtlFound |= rhs->rtlFound;
    // Preserve lhs lineAttribute — the line attribute was set on the original
    // row (start of the logical line); continuations are typically normal-width.
    if (!rhs->externalAttributes) {
        return;
    }
    iTermExternalAttributeIndex *lhsAttrs = iTermMetadataGetExternalAttributesIndexCreatingIfNeeded(lhs);
    iTermExternalAttributeIndex *eaIndex =
        [iTermExternalAttributeIndex concatenationOf:lhsAttrs
                                              length:lhsLength
                                                with:iTermImmutableMetadataGetExternalAttributesIndex(*rhs)
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
    iTermMetadataInit(obj, rhs->timestamp, lhs->rtlFound || rhs->rtlFound, eaIndex, lhs->lineAttribute);
}

void iTermMetadataInitCopyingSubrange(iTermMetadata *obj,
                                      iTermImmutableMetadata *source,
                                      int start,
                                      int length) {
    id<iTermExternalAttributeIndexReading> sourceIndex = iTermImmutableMetadataGetExternalAttributesIndex(*source);
    iTermExternalAttributeIndex *eaIndex = [sourceIndex subAttributesFromIndex:start maximumLength:length];
    iTermMetadataInit(obj,
                      source->timestamp,
                      source->rtlFound,
                      eaIndex,
                      source->lineAttribute);
}

iTermMetadata iTermMetadataDefault(void) {
    return (iTermMetadata){ .timestamp = 0,
        .externalAttributes = NULL,
        .rtlFound = NO,
        .lineAttribute = iTermLineAttributeSingleWidth
    };
}

iTermImmutableMetadata iTermImmutableMetadataDefault(void) {
    return iTermMetadataMakeImmutable(iTermMetadataDefault());
}

void iTermMetadataReset(iTermMetadata *obj) {
    obj->timestamp = 0;
    obj->rtlFound = NO;
    obj->lineAttribute = iTermLineAttributeSingleWidth;
    iTermMetadataSetExternalAttributes(obj, NULL);
}

NSString *iTermMetadataShortDescription(iTermMetadata metadata, int length) {
    return [NSString stringWithFormat:@"<timestamp=%@ ea=%@ rtl=%@ lineAttr=%d>",
            @(metadata.timestamp),
            iTermMetadataGetExternalAttributesIndex(metadata),
            @(metadata.rtlFound),
            (int)metadata.lineAttribute];
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
    [decoder decodeBool:&temp.rtlFound];
    int lineAttr = 0;
    if ([decoder decodeInt:&lineAttr]) {
        temp.lineAttribute = (iTermLineAttribute)lineAttr;
    }
    iTermExternalAttributeIndex *attr = [iTermExternalAttributeIndex fromData:attrData];
    iTermMetadataSetExternalAttributes(&temp, attr);
    NSArray *result = iTermMetadataEncodeToArray(temp);
    iTermMetadataRelease(temp);
    return result;
}

NSData *iTermMetadataEncodeToData(iTermMetadata metadata) {
    return iTermImmutableMetadataEncodeToData(iTermMetadataMakeImmutable(metadata));
}

NSData *iTermImmutableMetadataEncodeToData(iTermImmutableMetadata metadata) {
    iTermTLVEncoder *encoder = [[[iTermTLVEncoder alloc] init] autorelease];
    [encoder encodeDouble:metadata.timestamp];
    iTermExternalAttributeIndex *attr = iTermImmutableMetadataGetExternalAttributesIndex(metadata);
    [encoder encodeData:[attr data] ?: [NSData data]];
    [encoder encodeBool:metadata.rtlFound];
    [encoder encodeInt:(int)metadata.lineAttribute];
    return encoder.data;
}

iTermMetadata iTermMetadataDecodedFromData(NSData *data) {
    iTermMetadata temp;
    memset(&temp, 0, sizeof(temp));
    iTermTLVDecoder *decoder = [[[iTermTLVDecoder alloc] initWithData:data] autorelease];
    if (![decoder decodeDouble:&temp.timestamp]) {
        return iTermMetadataDefault();
    }
    NSData *attrData = [decoder decodeData];
    if (!attrData) {
        return iTermMetadataDefault();
    }
    [decoder decodeBool:&temp.rtlFound];
    int lineAttr = 0;
    if ([decoder decodeInt:&lineAttr]) {
        temp.lineAttribute = (iTermLineAttribute)lineAttr;
    }
    iTermExternalAttributeIndex *attr = [iTermExternalAttributeIndex fromData:attrData];
    iTermMetadataSetExternalAttributes(&temp, attr);
    return temp;
}
