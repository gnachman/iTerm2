//
//  iTermClientServerProtocolMessageBox.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/16/20.
//

#import <Foundation/Foundation.h>

#import "iTermMultiServerMessage.h"
#import "iTermMultiServerProtocol.h"

NS_ASSUME_NONNULL_BEGIN

@interface iTermClientServerProtocolMessageBox: NSObject
@property (nonatomic) iTermMultiServerMessage *message;
@property (nullable, nonatomic, readonly) iTermMultiServerServerOriginatedMessage *decoded;

+ (instancetype)withMessage:(iTermMultiServerMessage *)message;
@end

NS_ASSUME_NONNULL_END
