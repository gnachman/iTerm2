//
//  iTermTLVCodec.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 9/20/21.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface iTermTLVEncoder: NSObject
@property (nonatomic, readonly) NSData *data;

- (void)encodeInt:(int)i;
- (void)encodeUnsignedInt:(unsigned int)i;
- (void)encodeData:(NSData *)data;
- (void)encodeRange:(NSRange)range;
- (void)encodeBool:(BOOL)b;
- (void)encodeDouble:(double)d;
@end

@interface iTermTLVDecoder: NSObject
@property (nonatomic, readonly) NSData *data;
@property (nonatomic, readonly) BOOL finished;
- (instancetype)initWithData:(NSData *)data NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

- (BOOL)decodeInt:(int *)i;
- (BOOL)decodeUnsignedInt:(unsigned int *)i;
- (NSData * _Nullable)decodeData;
- (BOOL)decodeRange:(NSRange *)range;
- (BOOL)decodeBool:(BOOL *)b;
- (BOOL)decodeDouble:(double *)d;

@end

NS_ASSUME_NONNULL_END
