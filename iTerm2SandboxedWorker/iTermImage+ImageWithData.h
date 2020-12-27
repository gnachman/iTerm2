//
//  iTermImage+ImageWithData.h
//  iTerm2
//
//  Created by Benedek Kozma on 2020. 12. 23..
//

#import "iTermImage.h"

NS_ASSUME_NONNULL_BEGIN

@interface iTermImage(ImageWithData)

- (instancetype)initWithData:(NSData *)data;

@end

NS_ASSUME_NONNULL_END
