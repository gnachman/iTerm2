//
//  EquivalenceClassSet.h
//  iTerm
//
//  Created by George Nachman on 12/28/11.
//  Copyright (c) 2011 Georgetech. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface EquivalenceClassSet : NSObject {
    NSMutableDictionary *index_;
    NSMutableDictionary *classes_;
}

- (NSArray *)valuesEqualTo:(NSObject<NSCopying> *)target;
- (void)setValue:(NSObject<NSCopying> *)value equalToValue:(NSObject<NSCopying> *)otherValue;
- (void)removeValue:(NSObject<NSCopying> *)target;
- (NSArray *)classes;

@end
