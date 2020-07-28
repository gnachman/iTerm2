//
//  iTermGraphSQLEncoder.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 7/28/20.
//

#import "iTermGraphSQLEncoder.h"

@implementation iTermGraphSQLEncoder

- (instancetype)initWithRecord:(iTermEncoderGraphRecord *)record {
    self = [super init];
    if (self) {
        _root = record;
    }
    return self;
}

- (NSArray<NSString *> *)sqlStatementsForNextRevision:(void (^ NS_NOESCAPE)(iTermGraphDeltaEncoder *encoder))block {
    iTermGraphDeltaEncoder *encoder = [[iTermGraphDeltaEncoder alloc] initWithPreviousRevision:_root];
    block(encoder);
    NSMutableArray<NSString *> *sql = [NSMutableArray array];
    [encoder enumerateRecords:^(iTermEncoderGraphRecord * _Nullable before,
                                iTermEncoderGraphRecord * _Nullable after,
                                NSString *context) {
        // TODO
    }];
    return sql;
}

@end
