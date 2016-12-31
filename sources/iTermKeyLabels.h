//
//  iTermKeyLabels.h
//  iTerm2
//
//  Created by George Nachman on 12/30/16.
//
//

#import <Foundation/Foundation.h>

@interface iTermKeyLabels : NSObject
@property(nonatomic, copy) NSMutableDictionary<NSString *, NSString *> *map;
@property(nonatomic, copy) NSString *name;
@end
