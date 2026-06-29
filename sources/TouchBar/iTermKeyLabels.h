//
//  iTermKeyLabels.h
//  iTerm2
//
//  Created by George Nachman on 12/30/16.
//
//

#import <Foundation/Foundation.h>

@interface iTermKeyLabels : NSObject
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *map;
@property(nonatomic, copy) NSString *name;

@property(nonatomic, readonly) NSDictionary *dictionaryValue;

- (instancetype)initWithDictionary:(NSDictionary *)dict;

@end
