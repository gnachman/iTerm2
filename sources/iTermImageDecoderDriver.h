//
//  iTermImageDecoderDriver.h
//  iTerm2
//
//  Created by George Nachman on 8/30/16.
//
//

#import <Foundation/Foundation.h>

// Forks and execs the image decoder. Sends it a compressedImage. Reads back JSON describing a
// decompressed image.
@interface iTermImageDecoderDriver : NSObject

- (NSData *)jsonForCompressedImageData:(NSData *)compressedImageData;

@end
