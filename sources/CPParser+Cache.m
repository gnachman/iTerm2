//
//  CPParser+Cache.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 17/04/19.
//

#import "CPParser+Cache.h"

#import "DebugLogging.h"
#import "NSFileManager+iTerm.h"
#import "NSObject+iTerm.h"
#import "NSStringITerm.h"

#import <CoreParse/CoreParse.h>

static const char CPShiftReduceParserAssociatedObjectCacheKey;

@implementation CPShiftReduceParser (Cache)

+ (NSString *)it_keyWithBNF:(NSString *)bnf start:(NSString *)start {
    NSDictionary *info = [[NSBundle mainBundle] infoDictionary];
    NSString *version = info[@"CFBundleShortVersionString"];
    NSString *key = [NSString stringWithFormat:@"%@ %@ %@%@",
                     version,
                     NSStringFromClass(self),
                     bnf.it_contentHash,
                     start].it_contentHash;
    return key;
}

+ (instancetype)parserWithBNF:(NSString *)bnf start:(NSString *)start {
    __kindof CPParser *parser;
    NSString *key = [self it_keyWithBNF:bnf start:start];
    parser = [self.it_cache[key] firstObject];
    if (parser) {
        [self.it_cache[key] removeObjectAtIndex:0];
        return parser;
    }

    NSString *const file = [self it_pathToCacheForKey:key];
    parser = [self it_cachedFromFile:file];
    if (parser) {
        [parser it_setAssociatedObject:[key copy] forKey:(void *)&CPShiftReduceParserAssociatedObjectCacheKey];
        return parser;
    }

    parser = [self it_parserWithGrammarStart:start bnf:bnf];
    if (!parser) {
        return nil;
    }

    [parser it_setAssociatedObject:[key copy] forKey:(void *)&CPShiftReduceParserAssociatedObjectCacheKey];
    [parser it_writeToFile:file];
    return parser;
}

- (void)it_releaseParser {
    NSString *key = [self it_associatedObjectForKey:(void *)&CPShiftReduceParserAssociatedObjectCacheKey];
    if (!key) {
        return;
    }
    self.delegate = nil;
    NSMutableArray *array = [[CPShiftReduceParser it_cache] objectForKey:key];
    if (!array) {
        [[CPShiftReduceParser it_cache] setObject:[NSMutableArray arrayWithObject:self] forKey:key];
    } else {
        [array addObject:self];
    }
}

+ (NSString *)it_pathToCacheForKey:(NSString *)key {
    NSString *appSupport = [[NSFileManager defaultManager] applicationSupportDirectory];
    NSString *parsers = [appSupport stringByAppendingPathComponent:@"parsers"];
    NSString *file = [parsers stringByAppendingPathComponent:key];
    [[NSFileManager defaultManager] createDirectoryAtPath:parsers withIntermediateDirectories:YES attributes:nil error:nil];
    return file;
}

+ (NSMutableDictionary<NSString *, NSMutableArray *> *)it_cache {
    static NSMutableDictionary<NSString *, NSMutableArray *> *cache;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        cache = [NSMutableDictionary dictionary];
    });
    return cache;
}

+ (instancetype)it_cachedFromFile:(NSString *)file {
    if (!file) {
        return nil;
    }
    NSData *data = [NSData dataWithContentsOfFile:file];
    if (!data.length) {
        return nil;
    }
    @try {
        NSKeyedUnarchiver *unarchiver = [[NSKeyedUnarchiver alloc] initForReadingWithData:data];
        return [[self alloc] initWithCoder:unarchiver];
    } @catch (NSException *exception) {
        XLog(@"Cache at %@ busted, re-creating", file);
    }
    return nil;
}

+ (instancetype)it_parserWithGrammarStart:(NSString *)start bnf:(NSString *)bnf {
    NSError *error = nil;
    CPGrammar *grammar = [CPGrammar grammarWithStart:start
                                      backusNaurForm:bnf
                                               error:&error];

    if (!grammar) {
        XLog(@"Failed to create grammar: %@", error);
        return nil;
    }

    id parser = [self parserWithGrammar:grammar];
    if (!parser) {
        XLog(@"Failed to create parser");
        return nil;
    }

    return parser;
}

- (void)it_writeToFile:(NSString *)file {
    NSMutableData *data = [NSMutableData data];
    NSKeyedArchiver *coder = [[NSKeyedArchiver alloc] initForWritingWithMutableData:data];
    coder.outputFormat = NSPropertyListBinaryFormat_v1_0;
    [self encodeWithCoder:coder];
    [coder finishEncoding];
    [data writeToFile:file atomically:NO];
}

@end
