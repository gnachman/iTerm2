//
//  iTerm2SandboxedWorker.m
//  iTerm2SandboxedWorker
//
//  Created by Benedek Kozma on 2020. 12. 23..
//

#import <Foundation/Foundation.h>
#import "iTerm2SandboxedWorker.h"
#import "iTermImage+ImageWithData.h"

@implementation iTerm2SandboxedWorker

- (void)decodeImageFromData:(NSData *)imageData withReply:(void (^)(iTermImage *))reply {
    reply([[iTermImage alloc] initWithData:imageData]);
}

@end
