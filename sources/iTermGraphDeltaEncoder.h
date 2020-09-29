//
//  iTermGraphDeltaEncoder.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 7/28/20.
//

#import <Foundation/Foundation.h>

#import "iTermGraphEncoder.h"

NS_ASSUME_NONNULL_BEGIN

@interface iTermGraphDeltaEncoder: iTermGraphEncoder
@property (nonatomic, readonly, nullable) iTermEncoderGraphRecord *previousRevision;

- (instancetype)initWithKey:(NSString *)key
                 identifier:(NSString *)identifier
                 generation:(NSInteger)generation NS_UNAVAILABLE;

- (instancetype)initWithPreviousRevision:(iTermEncoderGraphRecord * _Nullable)previousRevision;

- (BOOL)enumerateRecords:(void (^)(iTermEncoderGraphRecord * _Nullable before,
                                   iTermEncoderGraphRecord * _Nullable after,
                                   NSNumber *parent,
                                   NSString *path,
                                   BOOL *stop))block;

@end

NS_ASSUME_NONNULL_END
