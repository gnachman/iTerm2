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

- (NSArray *)valuesEqualTo:(NSObject *)target;
- (void)setValue:(NSObject *)value equalToValue:(NSObject *)otherValue;
- (void)removeValue:(NSObject *)target;
- (NSArray *)classes;

@end
