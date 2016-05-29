//
//  iTermAutoMasterParser.m
//  iTerm2
//
//  Created by George Nachman on 3/22/16.
//
//

#import "iTermAutoMasterParser.h"

#import "DebugLogging.h"

// Represents an entry in /etc/auto_master.
@interface iTermAutoMasterEntry : NSObject
@property(nonatomic, copy) NSString *mountpoint;
@property(nonatomic, copy) NSString *map;
@property(nonatomic, copy) NSString *options;

+ (instancetype)entryWithLine:(NSString *)line;

@end

@implementation iTermAutoMasterEntry

+ (instancetype)entryWithLine:(NSString *)line {
    NSRange hashRange = [line rangeOfString:@"#"];
    if (hashRange.location != NSNotFound) {
        if (hashRange.location > 0) {
            line = [line substringToIndex:hashRange.location];
        } else if (hashRange.location == 0) {
            line = @"";
        }
    }
    
    NSScanner *scanner = [[[NSScanner alloc] initWithString:line] autorelease];
    NSString *mountpoint = nil;
    NSString *map = nil;
    NSString *options = nil;
    if (![scanner scanUpToCharactersFromSet:[NSCharacterSet whitespaceCharacterSet]
                                 intoString:&mountpoint]) {
        return nil;
    }
    [scanner scanCharactersFromSet:[NSCharacterSet whitespaceCharacterSet] intoString:nil];
    if (![scanner scanUpToCharactersFromSet:[NSCharacterSet whitespaceCharacterSet]
                                 intoString:&map]) {
        return nil;
    }
    [scanner scanCharactersFromSet:[NSCharacterSet whitespaceCharacterSet] intoString:nil];
    // options are optional.
    [scanner scanUpToCharactersFromSet:[NSCharacterSet whitespaceCharacterSet]
                            intoString:&options];

    iTermAutoMasterEntry *entry = [[[iTermAutoMasterEntry alloc] init] autorelease];
    entry.mountpoint = mountpoint;
    entry.map = map;
    entry.options = options;
    return entry;
}

- (void)dealloc {
    [_mountpoint release];
    [_map release];
    [_options release];
    [super dealloc];
}

@end

@implementation iTermAutoMasterParser {
    NSArray<iTermAutoMasterEntry *> *_entries;
}

+ (instancetype)sharedInstance {
    static id object;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        object = [[self alloc] init];
    });
    return object;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        NSMutableArray<iTermAutoMasterEntry *> *entries = [NSMutableArray array];
        NSData *data = [NSData dataWithContentsOfFile:@"/etc/auto_master"];
        // The actual character set for this file doesn't seem to be defined. This is my guess.
        NSString *string = [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease];
        NSArray<NSString *> *lines = [string componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
        
        for (NSString *line in lines) {
            iTermAutoMasterEntry *entry = [iTermAutoMasterEntry entryWithLine:line];
            if (entry) {
                [entries addObject:entry];
            }
        }
        _entries = [entries retain];
    }
    return self;
}

- (NSArray<NSString *> *)mountpointsWithMap:(NSString *)map {
    NSMutableArray<NSString *> *result = [NSMutableArray array];
    for (iTermAutoMasterEntry *entry in _entries) {
        if ([entry.map isEqualToString:map]) {
            DLog(@"Found NFS automounter at %@", entry.mountpoint);
            [result addObject:entry.mountpoint];
        }
    }
    return result;
}

@end
