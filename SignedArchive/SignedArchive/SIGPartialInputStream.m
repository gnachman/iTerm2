//
//  SIGPartialInputStream.m
//  SignedArchive
//
//  Created by George Nachman on 12/17/18.
//  Copyright © 2018 George Nachman. All rights reserved.
//

#import "SIGPartialInputStream.h"

@interface SIGPartialInputStream()<NSStreamDelegate>
@end

@implementation SIGPartialInputStream {
    NSInputStream *_realInputStream;
    NSUInteger _bytesLeft;
    NSRange _range;
    id<NSStreamDelegate> _delegate;
}

- (instancetype)initWithURL:(NSURL *)URL range:(NSRange)range {
    self = [super initWithURL:URL];
    if (self) {
        _realInputStream = [[NSInputStream alloc] initWithURL:URL];
        _realInputStream.delegate = self;
        self.delegate = self;
        _range = range;
    }
    return self;
}

#pragma mark - NSStream Overrides

- (void)setDelegate:(id<NSStreamDelegate>)delegate {
    if (delegate == nil) {
        _delegate = self;
    } else {
        _delegate = delegate;
    }
}

- (id<NSStreamDelegate>)delegate {
    return _delegate;
}

- (void)open {
    [_realInputStream open];
    [_realInputStream setProperty:@(_range.location)
                           forKey:NSStreamFileCurrentOffsetKey];
    _bytesLeft = _range.length;
}

- (void)close {
    [_realInputStream close];
}

- (void)scheduleInRunLoop:(NSRunLoop *)aRunLoop forMode:(NSString *)mode {
    [_realInputStream scheduleInRunLoop:aRunLoop forMode:mode];
}

- (void)removeFromRunLoop:(NSRunLoop *)aRunLoop forMode:(NSString *)mode {
    [_realInputStream removeFromRunLoop:aRunLoop forMode:mode];
}

- (id)propertyForKey:(NSString *)key {
    return [_realInputStream propertyForKey:key];
}

- (BOOL)setProperty:(id)property forKey:(NSString *)key {
    return [_realInputStream setProperty:property forKey:key];
}

- (NSStreamStatus)streamStatus {
    return [_realInputStream streamStatus];
}

- (NSError *)streamError {
    return [_realInputStream streamError];
}

#pragma mark - NSInputStream overrides

- (NSInteger)read:(uint8_t *)buffer maxLength:(NSUInteger)maxLength {
    const NSInteger realMaxLength = MIN(_bytesLeft, maxLength);
    const NSInteger numberOfBytesRead = [_realInputStream read:buffer maxLength:realMaxLength];
    _bytesLeft -= numberOfBytesRead;
    
    return numberOfBytesRead;
}

- (BOOL)getBuffer:(uint8_t **)buffer length:(NSUInteger *)len {
    return NO;
}

- (BOOL)hasBytesAvailable {
    if (_bytesLeft <= 0) {
        return NO;
    }
    
    return [_realInputStream hasBytesAvailable];
}

#pragma mark - NSInputStreamDelegate

- (void)stream:(NSStream *)aStream handleEvent:(NSStreamEvent)eventCode {
    if (self.delegate == self) {
        return;
    }
    [self.delegate stream:aStream handleEvent:eventCode];
}

@end
