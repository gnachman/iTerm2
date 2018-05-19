//
//  CPJSONParser.h
//  CoreParse
//
//  Created by Tom Davie on 29/03/2011.
//  Copyright 2011 In The Beginning... All rights reserved.
//

#import <Foundation/Foundation.h>

/**
 * The CPJSONParser class is a demonstration of CoreParse.
 * 
 * The parser deals with all JSON except for unicode encoded characters.  The reason for not dealing with this corner case is that this parser is simply to demonstrate how to use CoreParse, and
 * the code needed to process unicode characters is non-trivial, and not particularly relevant to the demonstration.
 */
@interface CPJSONParser : NSObject

/**
 * Parses a JSON string and returns a standard objective-c data structure reflecting it:
 * 
 * JSON numbers and booleans are returned as NSNumbers; JSON strings as NSStrings; `null` as an NSNull object; JSON arrays are returned as NSArrays; finally JSON objects are returned as NSDictionarys.
 *
 * @param json The JSON string to parse.
 */
- (id<NSObject>)parse:(NSString *)json;

@end
