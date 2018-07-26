//
//  NSJSONSerialization+iTerm.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 5/19/18.
//

#import <Foundation/Foundation.h>

@interface NSJSONSerialization (iTerm)

// Converts object to a JSON string. Object may be a string, number, dictionary,
// or array. Returns nil if it's not.
+ (NSString *)it_jsonStringForObject:(id)object;

// Converts a string to JSON.
+ (id)it_objectForJsonString:(NSString *)string;

+ (id)it_objectForJsonString:(NSString *)string error:(out NSError **)error;

@end
