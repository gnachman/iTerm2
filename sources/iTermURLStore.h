//
//  iTermURLStore.h
//  iTerm2
//
//  Created by George Nachman on 3/19/17.
//
//

#import <Foundation/Foundation.h>
#import "iTermEncoderAdapter.h"

NS_ASSUME_NONNULL_BEGIN

// See https://bugzilla.gnome.org/show_bug.cgi?id=779734 for the original discussion.
@interface iTermURLStore : NSObject<iTermGraphCodable>
@property(nonatomic, readonly) NSInteger generation;

+ (instancetype)sharedInstance;
- (unsigned int)codeForURL:(NSURL *)url withParams:(NSString * _Nullable)params;
- (NSURL * _Nullable)urlForCode:(unsigned int)code;
- (NSString * _Nullable)paramWithKey:(NSString *)key forCode:(unsigned int)code;
- (void)releaseCode:(unsigned int)code;
- (void)retainCode:(unsigned int)code;

- (NSDictionary *)dictionaryValue;
- (void)loadFromDictionary:(NSDictionary *)dictionary;
- (void)loadFromGraphRecord:(iTermEncoderGraphRecord *)record;

@end

NS_ASSUME_NONNULL_END
