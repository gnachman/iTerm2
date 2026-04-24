//
//  ObjCExceptions.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 5/25/22.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Run block, catching objective C exceptions. Returns the exception or nil.
NSError * _Nullable ObjCTryImpl(void (^NS_NOESCAPE block)(void));

NS_ASSUME_NONNULL_END
