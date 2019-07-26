//
//  iTermFileDescriptorMultiClient+Protected.h
//  iTerm2
//
//  Created by George Nachman on 12/31/19.
//

#import "iTermFileDescriptorMultiClient.h"

@interface iTermFileDescriptorMultiClient() {
@protected
    int _readFD;
    int _writeFD;
}
@end
