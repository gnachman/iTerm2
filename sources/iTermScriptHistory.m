//
//  iTermScriptHistory.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/19/18.
//

#import "iTermScriptHistory.h"

#import "NSArray+iTerm.h"
#import "NSStringITerm.h"
#import "iTermAPIServer.h"

NS_ASSUME_NONNULL_BEGIN

NSString *const iTermScriptHistoryEntryDidChangeNotification = @"iTermScriptHistoryEntryDidChangeNotification";
NSString *const iTermScriptHistoryEntryDelta = @"delta";
NSString *const iTermScriptHistoryEntryFieldKey = @"field";
NSString *const iTermScriptHistoryEntryFieldLogsValue = @"logs";
NSString *const iTermScriptHistoryEntryFieldRPCValue = @"rpc";

@implementation iTermScriptHistoryEntry {
    NSDateFormatter *_dateFormatter;
    NSMutableArray<NSString *> *_logLines;
    NSMutableArray<NSString *> *_callEntries;
}

- (instancetype)initWithName:(NSString *)name identifier:(NSString *)identifier {
    self = [super init];
    if (self) {
        _name = [name copy];
        _identifier = [identifier copy];
        _startDate = [NSDate date];
        _isRunning = YES;
        _dateFormatter = [[NSDateFormatter alloc] init];
        _logLines = [NSMutableArray array];
        _callEntries = [NSMutableArray array];
        _dateFormatter.dateFormat = [NSDateFormatter dateFormatFromTemplate:@"Ld jj:mm:ss"
                                                                    options:0
                                                                     locale:[NSLocale currentLocale]];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(apiServerDidReceiveMessage:)
                                                     name:iTermAPIServerDidReceiveMessage
                                                   object:identifier];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(apiServerWillSendMessage:)
                                                     name:iTermAPIServerWillSendMessage
                                                   object:identifier];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)apiServerDidReceiveMessage:(NSNotification *)notification {
    ITMClientOriginatedMessage *request = notification.userInfo[@"request"];
    [self addClientOriginatedRPC:[request.description stringByAppendingString:@"\n"]];
}

- (void)apiServerWillSendMessage:(NSNotification *)notification {
    ITMServerOriginatedMessage *message = notification.userInfo[@"message"];
    [self addServerOriginatedRPC:[message.description stringByAppendingString:@"\n"]];
}

- (void)addOutput:(NSString *)output {
    NSString *timestamp = [NSString stringWithFormat:@"\n%@: ", [_dateFormatter stringFromDate:[NSDate date]]];
    BOOL trimmed = [output hasSuffix:@"\n"];
    if (trimmed) {
        output = [output substringWithRange:NSMakeRange(0, output.length - 1)];
    }
    output = [output stringByReplacingOccurrencesOfString:@"\n" withString:timestamp];
    if (trimmed) {
        output = [output stringByAppendingString:@"\n"];
    }

    if (!_lastLogLineContinues) {
        output = [NSString stringWithFormat:@"%@: %@", [_dateFormatter stringFromDate:[NSDate date]], output];
    }

    [self appendLogs:output];
    [[NSNotificationCenter defaultCenter] postNotificationName:iTermScriptHistoryEntryDidChangeNotification
                                                        object:self
                                                      userInfo:@{ iTermScriptHistoryEntryDelta: output,
                                                                  iTermScriptHistoryEntryFieldKey: iTermScriptHistoryEntryFieldLogsValue }];
}

- (void)addClientOriginatedRPC:(NSString *)rpc {
    NSString *string = [NSString stringWithFormat:@"Script → iTerm2 %@:\n%@\n", [_dateFormatter stringFromDate:[NSDate date]], rpc];
    [self appendCalls:string];
    [[NSNotificationCenter defaultCenter] postNotificationName:iTermScriptHistoryEntryDidChangeNotification
                                                        object:self
                                                      userInfo:@{ iTermScriptHistoryEntryDelta: string,
                                                                  iTermScriptHistoryEntryFieldKey: iTermScriptHistoryEntryFieldRPCValue }];
}

- (void)addServerOriginatedRPC:(NSString *)rpc {
    NSString *string = [NSString stringWithFormat:@"Script ← iTerm2 %@:\n%@\n", [_dateFormatter stringFromDate:[NSDate date]], rpc];
    [self appendCalls:string];
    [[NSNotificationCenter defaultCenter] postNotificationName:iTermScriptHistoryEntryDidChangeNotification
                                                        object:self
                                                      userInfo:@{ iTermScriptHistoryEntryDelta: string,
                                                                  iTermScriptHistoryEntryFieldKey: iTermScriptHistoryEntryFieldRPCValue }];
}

- (void)stopRunning {
    _isRunning = NO;
    [[NSNotificationCenter defaultCenter] postNotificationName:iTermScriptHistoryEntryDidChangeNotification
                                                        object:self];
}

- (void)appendLogs:(NSString *)delta {
    if (delta.length == 0) {
        return;
    }
    BOOL endsWithNewline = [delta hasSuffix:@"\n"];
    if (endsWithNewline) {
        delta = [delta substringWithRange:NSMakeRange(0, delta.length - 1)];
    }
    NSArray<NSString *> *newLines = [delta componentsSeparatedByString:@"\n"];
    if (_lastLogLineContinues) {
        NSString *amended = [_logLines.lastObject stringByAppendingString:newLines.firstObject];
        newLines = [newLines subarrayWithRange:NSMakeRange(1, newLines.count - 1)];
        _logLines[_logLines.count - 1] = amended;

    }
    [_logLines addObjectsFromArray:newLines];
    _lastLogLineContinues = !endsWithNewline;

    while (_logLines.count > 1000) {
        [_logLines removeObjectAtIndex:0];
    }
}

- (void)appendCalls:(NSString *)delta {
    [_callEntries addObject:delta];
    while (_callEntries.count > 100) {
        [_callEntries removeObjectAtIndex:0];
    }
}

@end

NSString *const iTermScriptHistoryNumberOfEntriesDidChangeNotification = @"iTermScriptHistoryNumberOfEntriesDidChangeNotification";

@implementation iTermScriptHistory {
    NSMutableArray<iTermScriptHistoryEntry *> *_entries;
}

+ (instancetype)sharedInstance {
    static id instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[self alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _entries = [NSMutableArray array];
    }
    return self;
}

- (NSArray<iTermScriptHistoryEntry *> *)runningEntries {
    return [self.entries filteredArrayUsingBlock:^BOOL(iTermScriptHistoryEntry *anObject) {
        return anObject.isRunning;
    }];
}

- (void)addHistoryEntry:(iTermScriptHistoryEntry *)entry {
    [_entries addObject:entry];
    [[NSNotificationCenter defaultCenter] postNotificationName:iTermScriptHistoryNumberOfEntriesDidChangeNotification
                                                        object:self];
}

- (iTermScriptHistoryEntry *)entryWithIdentifier:(NSString *)identifier {
    return [_entries objectPassingTest:^BOOL(iTermScriptHistoryEntry *element, NSUInteger index, BOOL *stop) {
        return [element.identifier isEqualToString:identifier];
    }];
}

@end

NS_ASSUME_NONNULL_END

