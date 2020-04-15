//
//  iTermClientServerProtocol.h
//  iTerm2
//
//  Created by George Nachman on 7/25/19.
//

#import "iTermFileDescriptorServer.h"
#include <sys/socket.h>

extern const int ITERM_MULTISERVER_MAGIC;

typedef struct {
    int valid;
    struct msghdr message;
    iTermFileDescriptorControlMessage controlBuffer;

    // "real" storage that message iovectors may choose to use.
    struct iovec ioVectors[1];
} iTermClientServerProtocolMessage;

typedef struct {
    ssize_t offset;
    iTermClientServerProtocolMessage *message;
} iTermClientServerProtocolMessageParser;

typedef struct {
    ssize_t offset;
    iTermClientServerProtocolMessage *message;
} iTermClientServerProtocolMessageEncoder;

void iTermClientServerProtocolMessageInitialize(iTermClientServerProtocolMessage *message);

void iTermClientServerProtocolMessageEnsureSpace(iTermClientServerProtocolMessage *message,
                                                 ssize_t spaceNeeded);

void iTermClientServerProtocolMessageFree(iTermClientServerProtocolMessage *message);

int iTermClientServerProtocolParseTaggedInt(iTermClientServerProtocolMessageParser *parser,
                                            void *out,
                                            size_t size,
                                            int tag);

int iTermClientServerProtocolParseTaggedString(iTermClientServerProtocolMessageParser *parser,
                                               char **out,
                                               int tag);

int iTermClientServerProtocolParseTaggedStringArray(iTermClientServerProtocolMessageParser *parser,
                                                    char ***arrayOut,
                                                    int *countOut,
                                                    int tag);

int iTermClientServerProtocolEncodeTaggedInt(iTermClientServerProtocolMessageEncoder *encoder,
                                             void *valuePtr,
                                             size_t size,
                                             int tag);

int iTermClientServerProtocolEncodeTaggedString(iTermClientServerProtocolMessageEncoder *encoder,
                                                const char *string,
                                                int tag);

int iTermClientServerProtocolEncodeTaggedStringArray(iTermClientServerProtocolMessageEncoder *encoder,
                                                     char **array,
                                                     int count,
                                                     int tag);

void iTermEncoderCommit(iTermClientServerProtocolMessageEncoder *encoder);
