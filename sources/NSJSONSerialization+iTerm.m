//
//  NSJSONSerialization+iTerm.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 5/19/18.
//

#import "NSJSONSerialization+iTerm.h"

#import "DebugLogging.h"
#import "NSStringITerm.h"

@implementation NSJSONSerialization (iTerm)

+ (NSString *)it_jsonStringForObject:(id)object {
    NSError *error = nil;
    NSData *json = nil;

    if (!object) {
        return nil;
    }

    if ([NSJSONSerialization isValidJSONObject:object]) {
        json = [self dataWithJSONObject:object
                                options:0
                                  error:&error];
        if (error) {
            XLog(@"Failed to json encode value %@: %@", object, error);
            return nil;
        }
    } else if ([object isKindOfClass:[NSString class]]) {
        json = [[object jsonEncodedString] dataUsingEncoding:NSUTF8StringEncoding];
    } else if ([object isKindOfClass:[NSNumber class]]) {
        json = [[object stringValue] dataUsingEncoding:NSUTF8StringEncoding];
    }
    if (!json) {
        return nil;
    }

    return [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding];
}

+ (id)it_objectForJsonString:(NSString *)string {
    NSError *error;
    NSData *data = [string dataUsingEncoding:NSUTF8StringEncoding];
    return [NSJSONSerialization JSONObjectWithData:data
                                           options:NSJSONReadingAllowFragments
                                             error:&error];
}

@end
