//
//  iTermWebSocketFrameBuilder.m
//  iTerm2
//
//  Created by George Nachman on 11/4/16.
//
//

#import "iTermWebSocketFrameBuilder.h"
#import "iTermWebSocketFrame.h"

@implementation iTermWebSocketFrameBuilder {
    NSMutableData *_data;
    iTermWebSocketFrame *_fragment;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _data = [[NSMutableData alloc] init];
    }
    return self;
}

- (void)dealloc {
    [_data release];
    [super dealloc];
}

- (void)addData:(NSData *)data frame:(void (^)(iTermWebSocketFrame *, BOOL *))frameBlock {
    [_data appendData:data];

    __block int64_t offset = 0;
    __block BOOL eof = NO;
    while (!eof) {
        iTermWebSocketFrame *frame = [iTermWebSocketFrame frameWithDataSource:^unsigned char *(int64_t bytesWanted) {
            if (_data.length < bytesWanted) {
                eof = YES;
                return NULL;
            } else {
                offset += bytesWanted;
                return _data.mutableBytes + offset;
            }
        }];
        if (!eof) {
            [_data replaceBytesInRange:NSMakeRange(0, offset) withBytes:"" length:0];
        }
        if (frame) {
            if (_fragment) {
                [_fragment appendFragment:frame];
                if (_fragment.fin) {
                    BOOL stop = NO;
                    frameBlock(_fragment, &stop);
                    [_fragment release];
                    _fragment = nil;
                    if (stop) {
                        return;
                    }
                }
            } else {
                if (frame.fin) {
                    BOOL stop = NO;
                    frameBlock(frame, &stop);
                    if (stop) {
                        return;
                    }
                } else {
                    _fragment = [frame retain];
                }
            }
        }
    }
}

@end
