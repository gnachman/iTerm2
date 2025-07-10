//
//  iTermColorVectorCache.h
//  iTerm2
//
//  Created by Claude on 2025-01-10.
//

#import <Foundation/Foundation.h>
#import <simd/simd.h>
#import "iTermColorMap.h"

NS_ASSUME_NONNULL_BEGIN

@interface iTermColorVectorCache : NSObject

- (vector_float4)vectorForColor:(NSColor *)color
                     colorSpace:(NSColorSpace *)colorSpace;

- (void)storeVector:(vector_float4)vector
            forKey:(iTermColorMapKey)key
         colorSpace:(NSColorSpace *)colorSpace;

- (BOOL)getVector:(vector_float4 *)outVector
           forKey:(iTermColorMapKey)key
       colorSpace:(NSColorSpace *)colorSpace;

- (void)clear;
- (void)clearKey:(iTermColorMapKey)key;

@end

NS_ASSUME_NONNULL_END