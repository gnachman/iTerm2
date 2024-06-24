//
//  ComparableNSObject.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 6/24/24.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface ComparableNSObject: NSObject
- (NSComparisonResult)compare:(id)other;
@end

NS_ASSUME_NONNULL_END
