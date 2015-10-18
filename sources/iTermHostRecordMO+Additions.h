//
//  iTermHostRecordAdditions.h
//  iTerm2
//
//  Created by George Nachman on 10/12/15.
//
//

#import <Foundation/Foundation.h>
#import "iTermHostRecordMO.h"

@interface iTermHostRecordMO (Additions)

+ (instancetype)hostRecordInContext:(NSManagedObjectContext *)context;
+ (NSString *)entityName;
- (NSString *)hostKey;

@end
