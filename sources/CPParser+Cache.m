//
//  CPParser+Cache.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 17/04/19.
//

#import "CPParser+Cache.h"

#import "DebugLogging.h"
#import "NSFileManager+iTerm.h"
#import "NSStringITerm.h"

#import <CoreParse/CoreParse.h>

@implementation CPShiftReduceParser (Cache)

+ (instancetype)parserWithBNF:(NSString *)bnf start:(NSString *)start {
    NSDictionary *info = [[NSBundle mainBundle] infoDictionary];
    NSString *version = info[@"CFBundleShortVersionString"];
    NSString *key = [NSString stringWithFormat:@"%@ %@ %@%@",
                     version,
                     NSStringFromClass(self),
                     bnf.it_contentHash,
                     start].it_contentHash;
    __kindof CPParser *parser;
    parser = self.it_cache[key];
    if (parser) {
        return parser;
    }

    NSString *const file = [self it_pathToCacheForKey:key];
    parser = [self it_cachedFromFile:file];
    if (parser) {
        return parser;
    }

    parser = [self it_parserWithGrammarStart:start bnf:bnf];
    if (!parser) {
        return nil;
    }

    [parser it_writeToFile:file];

    self.it_cache[key] = parser;
    return parser;
}

+ (NSString *)it_pathToCacheForKey:(NSString *)key {
    NSString *appSupport = [[NSFileManager defaultManager] applicationSupportDirectory];
    NSString *parsers = [appSupport stringByAppendingPathComponent:@"parsers"];
    NSString *file = [parsers stringByAppendingPathComponent:key];
    [[NSFileManager defaultManager] createDirectoryAtPath:parsers withIntermediateDirectories:YES attributes:nil error:nil];
    return file;
}

+ (NSMutableDictionary<NSString *, id> *)it_cache {
    static NSMutableDictionary<NSString *, id> *cache;
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
