//
//  iTermImage+ImageWithData.h
//  iTerm2
//
//  Created by Benedek Kozma on 2020. 12. 23..
//

#ifndef iTermImage_ImageWithData_h
#define iTermImage_ImageWithData_h

#import "iTermImage.h"

@interface iTermImage (ImageWithData)

- (instancetype)initWithData:(NSData *)data;

@end

#endif /* iTermImage_ImageWithData_h */
