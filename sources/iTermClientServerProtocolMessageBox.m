//
//  iTermClientServerProtocolMessageBox.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/16/20.
//

#import "iTermClientServerProtocolMessageBox.h"

#import "iTermClientServerProtocol.h"
#include <sys/un.h>

@implementation iTermClientServerProtocolMessageBox {
    iTermClientServerProtocolMessage _protocolMessage;
    BOOL _haveDecodedMessage;
    iTermMultiServerServerOriginatedMessage _decodedMessage;
}

+ (instancetype)withMessage:(iTermMultiServerMessage *)message {
    iTermClientServerProtocolMessageBox *box = [[iTermClientServerProtocolMessageBox alloc] init];
    iTermClientServerProtocolMessageInitialize(&box->_protocolMessage);
    if (message.fileDescriptor) {
        box->_protocolMessage.controlBuffer.cm.cmsg_len = CMSG_LEN(sizeof(int));
        box->_protocolMessage.controlBuffer.cm.cmsg_level = SOL_SOCKET;
        box->_protocolMessage.controlBuffer.cm.cmsg_type = SCM_RIGHTS;
        *((int *)CMSG_DATA(&box->_protocolMessage.controlBuffer.cm)) = message.fileDescriptor.intValue;
    }
    iTermClientServerProtocolMessageEnsureSpace(&box->_protocolMessage, message.data.length);
    memmove(box->_protocolMessage.message.msg_iov[0].iov_base, message.data.bytes, message.data.length);
    box->_message = message;
    return box;
}

- (iTermMultiServerServerOriginatedMessage *)decoded {
    if (_haveDecodedMessage) {
        return &_decodedMessage;
    }
    const int status = iTermMultiServerProtocolParseMessageFromServer(&_protocolMessage, &_decodedMessage);
    if (status) {
        DLog(@"Failed to decode message from server with status %d", status);
        return nil;
    }
    _haveDecodedMessage = YES;
    DLog(@"Decoded message from server:");
    iTermMultiServerProtocolLogMessageFromServer(&_decodedMessage);
    return &_decodedMessage;
}

- (void)dealloc {
    iTermClientServerProtocolMessageFree(&_protocolMessage);
    if (_haveDecodedMessage) {
        iTermMultiServerServerOriginatedMessageFree(&_decodedMessage);
    }
}

@end
