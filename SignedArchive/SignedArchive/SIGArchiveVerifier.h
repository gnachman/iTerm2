//
//  SIGArchiveVerifier.h
//  SignedArchive
//
//  Created by George Nachman on 12/17/18.
//  Copyright © 2018 George Nachman. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "SIGArchiveReader.h"

NS_ASSUME_NONNULL_BEGIN

@interface SIGArchiveVerifier : NSObject

@property (nonatomic, readonly) NSURL *url;
@property (nonatomic, readonly) BOOL verified;
@property (nonatomic, readonly, nullable) SIGArchiveReader *reader;

- (instancetype)initWithURL:(NSURL *)url NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

- (BOOL)smellsLikeSignedArchive:(out NSError **)error;

- (void)verifyWithCompletion:(void (^)(BOOL ok, NSError * _Nullable error))completion;

- (void)verifyAndWritePayloadToURL:(NSURL *)url
                        completion:(void (^)(BOOL ok, NSError * _Nullable error))completion;

// Must have called verifyWithCompletion: before.
- (BOOL)copyPayloadToURL:(NSURL *)url
                   error:(out NSError **)errorOut;
@end

NS_ASSUME_NONNULL_END
