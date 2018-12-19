//
//  SIGArchiveVerifier.h
//  SignedArchive
//
//  Created by George Nachman on 12/17/18.
//  Copyright © 2018 George Nachman. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface SIGArchiveVerifier : NSObject

@property (nonatomic, readonly) NSURL *url;

- (instancetype)initWithURL:(NSURL *)url NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

- (void)verifyWithCompletion:(void (^)(BOOL ok, NSError * _Nullable error))completion;

- (void)verifyAndWritePayloadToURL:(NSURL *)url
                        completion:(void (^)(BOOL ok, NSError * _Nullable error))completion;

@end

NS_ASSUME_NONNULL_END
