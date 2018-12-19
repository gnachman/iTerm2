//
//  SIGKeychain.h
//  SignedArchive
//
//  Created by George Nachman on 12/16/18.
//  Copyright © 2018 George Nachman. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface SIGKeychain : NSObject

@property (nonatomic, readonly) SecKeychainRef secKeychain;

+ (instancetype)sharedInstance;

- (instancetype)init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
