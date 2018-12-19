//
//  SIGArchiveBuilder.h
//  SignedArchive
//
//  Created by George Nachman on 12/16/18.
//  Copyright © 2018 George Nachman. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "SIGArchiveChunk.h"

NS_ASSUME_NONNULL_BEGIN

@class SIGIdentity;

@interface SIGArchiveBuilder : NSObject

@property (nonatomic, readonly) NSURL *payloadFileURL;
@property (nonatomic, readonly) SIGIdentity *identity;

- (instancetype)initWithPayloadFileURL:(NSURL *)payloadFileURL
                              identity:(SIGIdentity *)identity NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;

- (BOOL)writeToURL:(NSURL *)url
             error:(out NSError **)error;

@end

NS_ASSUME_NONNULL_END
