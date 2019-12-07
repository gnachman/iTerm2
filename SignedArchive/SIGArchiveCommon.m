//
//  SIGArchiveCommon.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 12/6/19.
//

#import "SIGArchiveCommon.h"

NSString *const SIGArchiveDigestTypeSHA2 = @"SHA2";

// NOTE: When adding a new key here, 
NSString *const SIGArchiveMetadataKeyVersion = @"version";
NSString *const SIGArchiveMetadataKeyDigestType = @"digest-type";

NSArray<NSString *> *SIGArchiveGetKnownKeys(void) {
    return @[
        SIGArchiveMetadataKeyVersion,
        SIGArchiveMetadataKeyDigestType
    ];
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
