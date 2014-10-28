//
//  VT100TmuxParser.h
//  iTerm
//
//  Created by George Nachman on 3/10/14.
//
//

#import <Foundation/Foundation.h>
#import "VT100Token.h"

@interface VT100TmuxParser : NSObject

- (void)decodeBytes:(unsigned char *)datap
             length:(int)datalen
          bytesUsed:(int *)rmlen
              token:(VT100Token *)result;

@end
