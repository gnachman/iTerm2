//
//  iTermURLStore.h
//  iTerm2
//
//  Created by George Nachman on 3/19/17.
//
//

#import <Foundation/Foundation.h>

@interface iTermURLStore : NSObject

+ (instancetype)sharedInstance;
- (unsigned short)codeForURL:(NSURL *)url withParams:(NSString *)params;
- (NSURL *)urlForCode:(unsigned short)code;
- (NSString *)paramWithKey:(NSString *)key forCode:(unsigned short)code;

- (NSDictionary *)dictionaryValue;
- (void)loadFromDictionary:(NSDictionary *)dictionary;

@end
