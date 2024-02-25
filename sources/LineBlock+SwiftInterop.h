//
//  LineBlock+SwiftInterop.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 2/29/24.
//

#import <Foundation/Foundation.h>
#import "LineBlock.h"

NS_ASSUME_NONNULL_BEGIN

@interface LineBlock(SwiftInterop)

- (NSData *)decompressedDataFromV4Data:(NSData *)v4data;

@end

NS_ASSUME_NONNULL_END
