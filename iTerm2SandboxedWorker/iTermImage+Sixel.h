//
//  iTermImage+Sixel.h
//  iTerm2SandboxedWorker
//
//  Created by Benedek Kozma on 2020. 12. 26..
//

#import "iTermImage.h"

NS_ASSUME_NONNULL_BEGIN

@interface iTermImage(Sixel)

- (instancetype)initWithSixelData:(NSData *)data;

@end

NS_ASSUME_NONNULL_END
