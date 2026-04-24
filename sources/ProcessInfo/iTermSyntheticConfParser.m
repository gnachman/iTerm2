//
//  iTermSyntheticConfParser.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 12/2/19.
//  Based on work by Erik Olofsson (erikolofsson at Github) in PR 409
//

#import "iTermSyntheticConfParser.h"
#import "iTermSyntheticConfParser+Private.h"

static NSString *iTermSyntheticDirectoryStringByPrependingSlashIfNotPresent(NSString *string) {
    if ([string hasPrefix:@"/"]) {
        return string;
    }
    return [@"/" stringByAppendingString:string];
}

@implementation iTermSyntheticDirectory

- (instancetype)initWithRoot:(NSString *)root target:(NSString *)target {
    self = [super init];
    if (self) {
        _root = iTermSyntheticDirectoryStringByPrependingSlashIfNotPresent(root);
        _target = iTermSyntheticDirectoryStringByPrependingSlashIfNotPresent(target);
    }
    return self;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@: %p root=%@ target=%@>",
            NSStringFromClass([self class]),
            self,
            _root,
            _target];
}

- (NSString *)pathByReplacingPrefixWithSyntheticRoot:(NSString *)dir {
    if ([dir isEqualToString:_target]) {
        return _root;
    }

    NSString *targetPrefix = [_target stringByAppendingString:@"/"];
    if ([dir hasPrefix:targetPrefix]) {
        return [dir stringByReplacingCharactersInRange:NSMakeRange(0, _target.length)
                                            withString:_root];
    }

    return nil;
}

@end

@implementation iTermSyntheticConfParser

+ (instancetype)sharedInstance {
    static dispatch_once_t onceToken;
    static id instance;
    dispatch_once(&onceToken, ^{
        instance = [[self alloc] initPrivate];
    });
    return instance;
}

+ (NSString *)contents {
    if (@available(macOS 10.15, *)) {
        NSFileManager *fileManager = [NSFileManager defaultManager];

        if (![fileManager fileExistsAtPath:@"/etc/synthetic.conf"]) {
            return @"";
        }

        NSString *contents = [NSString stringWithContentsOfFile:@"/etc/synthetic.conf"
                                                       encoding:NSUTF8StringEncoding
                                                          error:nil];
        return contents;
    }

    return @"";
}

+ (void)enumerateLinesInContent:(NSString *)contents block:(void (^)(NSString *))block {
    for (NSString *line in [contents componentsSeparatedByString:@"\n"]) {
        if ([line hasPrefix:@"#"]) {
            continue;
        }
        block(line);
    }
}

- (instancetype)initPrivate {
    self = [super init];
    if (self) {
        // The file only needs to be read once because modifications require a reboot.
        NSString *contents = [[self class] contents];

        NSMutableArray<iTermSyntheticDirectory *> *directories = [NSMutableArray array];

        [[self class] enumerateLinesInContent:contents block:^(NSString *line) {
            NSArray<NSString *> *mapping = [line componentsSeparatedByString:@"\t"];
            if (mapping.count != 2) {
                // An line with a single field is allowed but it's not interesting because such
                // paths do not need to be transformed.
                return;
            }

            NSString *root = [mapping[0] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            NSString *target = [mapping[1] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];

            if (root.length == 0 || target.length == 0) {
                return;
            }

            [directories addObject:[[iTermSyntheticDirectory alloc] initWithRoot:root target:target]];
        }];

        _syntheticDirectories = directories;
    }
    return self;
}

- (NSString *)pathByReplacingPrefixWithSyntheticRoot:(NSString *)dir {
    for (iTermSyntheticDirectory *mapping in _syntheticDirectories) {
        NSString *synthetic = [mapping pathByReplacingPrefixWithSyntheticRoot:dir];
        if (synthetic) {
            return synthetic;
        }
    }
    return dir;
}

@end
