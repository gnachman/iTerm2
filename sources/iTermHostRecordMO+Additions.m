//
//  iTermHostRecordAdditions.m
//  iTerm2
//
//  Created by George Nachman on 10/12/15.
//
//

#import "iTermHostRecordMO+Additions.h"

@implementation iTermHostRecordMO (Additions)

+ (instancetype)hostRecordInContext:(NSManagedObjectContext *)context {
    return [NSEntityDescription insertNewObjectForEntityForName:self.entityName
                                         inManagedObjectContext:context];
}

+ (NSString *)entityName {
    return @"HostRecord";
}

- (NSString *)hostKey {
    return [NSString stringWithFormat:@"%@@%@", self.username, self.hostname];
}

@end
