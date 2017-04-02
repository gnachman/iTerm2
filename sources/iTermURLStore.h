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

+ (instancetype)sharedInstance;
- (unsigned short)codeForURL:(NSURL *)url withParams:(NSString *)params;
- (NSURL *)urlForCode:(unsigned short)code;
- (NSString *)paramWithKey:(NSString *)key forCode:(unsigned short)code;
- (void)releaseCode:(unsigned short)code;
- (void)retainCode:(unsigned short)code;

- (NSDictionary *)dictionaryValue;
- (void)loadFromDictionary:(NSDictionary *)dictionary;

@end
