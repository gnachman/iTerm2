//
//  iTermURLStore.h
//  iTerm2
//
//  Created by George Nachman on 3/19/17.
//
//

#import <Foundation/Foundation.h>

// See https://bugzilla.gnome.org/show_bug.cgi?id=779734 for the original discussion.
@interface iTermURLStore : NSObject
@property(nonatomic, readonly) NSInteger generation;

+ (instancetype)sharedInstance;
- (unsigned int)codeForURL:(NSURL *)url withParams:(NSString *)params;
- (NSURL *)urlForCode:(unsigned int)code;
- (NSString *)paramWithKey:(NSString *)key forCode:(unsigned int)code;
- (void)releaseCode:(unsigned int)code;
- (void)retainCode:(unsigned int)code;

- (NSDictionary *)dictionaryValue;
- (void)loadFromDictionary:(NSDictionary *)dictionary;

@end
