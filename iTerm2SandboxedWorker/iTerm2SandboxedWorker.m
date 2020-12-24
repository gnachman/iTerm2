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
//    NSURL *url = [[NSURL alloc] initWithString:@"https://raw.githubusercontent.com/Cyberbeni/install-swift-tool/master/package.json"];
//    [self tryToAccessUrl:url completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
//        if (!error) {
            reply([[iTermImage alloc] initWithData:imageData]);
//        } else {
//            reply(nil);
//        }
//    }];
}

- (void)tryToAccessUrl:(NSURL *)url completionHandler:(void (^)(NSData *data, NSURLResponse *response, NSError *error))completionHandler {
    NSURLSessionDataTask *task = [NSURLSession.sharedSession dataTaskWithURL:url completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
        completionHandler(data, response, error);
    }];
    [task resume];
}

@end
