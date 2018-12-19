//
//  SIGPartialInputStream.h
//  SignedArchive
//
//  Created by George Nachman on 12/17/18.
//  Copyright © 2018 George Nachman. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface SIGPartialInputStream : NSInputStream

- (instancetype)initWithURL:(NSURL *)URL
                      range:(NSRange)range NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithURL:(NSURL *)url NS_UNAVAILABLE;
- (instancetype)initWithData:(NSData *)data NS_UNAVAILABLE;
- (instancetype)initWithFileAtPath:(NSString *)path NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
