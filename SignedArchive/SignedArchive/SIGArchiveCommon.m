//
//  SIGArchiveCommon.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 12/6/19.
//

#import "SIGArchiveCommon.h"

#import "SIGError.h"

NSString *const SIGArchiveDigestTypeSHA2 = @"SHA2";

// NOTE: When adding a new key here, 
NSString *const SIGArchiveMetadataKeyVersion = @"version";
NSString *const SIGArchiveMetadataKeyDigestType = @"digest-type";
NSString *const SIGArchiveMetadataKeyEncryption = @"encryption";
NSString *const SIGArchiveMetadataKeyKDF = @"kdf";
NSString *const SIGArchiveMetadataKeyKDFIterations = @"kdf-iterations";
NSString *const SIGArchiveMetadataKeyKDFSalt = @"kdf-salt";

NSArray<NSString *> *SIGArchiveGetKnownKeys(void) {
    return @[
        SIGArchiveMetadataKeyVersion,
        SIGArchiveMetadataKeyDigestType,
        SIGArchiveMetadataKeyEncryption,
        SIGArchiveMetadataKeyKDF,
        SIGArchiveMetadataKeyKDFIterations,
        SIGArchiveMetadataKeyKDFSalt
    ];
}

NSDictionary<NSString *, NSString *> *SIGArchiveParseMetadata(NSString *metadata, NSError **error) {
    NSMutableDictionary *dictionary = [NSMutableDictionary dictionary];
    NSArray<NSString *> *rows = [metadata componentsSeparatedByString:@"\n"];
    NSArray<NSString *> *knownKeys = SIGArchiveGetKnownKeys();

    for (NSString *row in rows) {
        NSInteger index = [row rangeOfString:@"="].location;
        if (index == NSNotFound) {
            continue;
        }
        NSString *key = [row substringToIndex:index];
        if (![knownKeys containsObject:key]) {
            continue;
        }
        if (dictionary[key]) {
            if (error) {
                *error = [SIGError errorWithCode:SIGErrorCodeMalformedMetadata];
            }
            return nil;
        }
        NSString *value = [row substringFromIndex:SIGAddNonnegativeInt64s(index, 1)];
        dictionary[key] = value;
    }
    return dictionary;
}

long long SIGAddNonnegativeInt64s(long long a, long long b) {
    assert(a >= 0);
    assert(b >= 0);

    unsigned long long ua = a;
    unsigned long long ub = b;
    unsigned long long sum = ua + ub;
    assert(sum >= ua && sum >= ub);
    return sum;
}
