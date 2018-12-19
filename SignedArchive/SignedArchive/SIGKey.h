//
//  SIGKey.h
//  SignedArchive
//
//  Created by George Nachman on 12/17/18.
//  Copyright © 2018 George Nachman. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface SIGKey : NSObject

@property (nonatomic, readonly) SecKeyRef secKey;

- (instancetype)initWithSecKey:(SecKeyRef)secKey NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
