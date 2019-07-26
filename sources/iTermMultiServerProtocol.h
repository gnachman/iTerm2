//
//  iTermMultiServerProtocol.h
//  iTerm2
//
//  Created by George Nachman on 7/25/19.
//

#import "iTermClientServerProtocol.h"

enum {
    iTermMultiServerProtocolVersionRejected = -1,
    iTermMultiServerProtocolVersion1 = 1
};

typedef enum {
    iTermMultiServerTagType,

    iTermMultiServerTagHandshakeRequestClientMaximumProtocolVersion,

    iTermMultiServerTagHandshakeResponseProtocolVersion,
    iTermMultiServerTagHandshakeResponseChildReportsNumChildren,
    iTermMultiServerTagHandshakeResponseProcessID,

    iTermMultiServerTagLaunchRequestPath,
    iTermMultiServerTagLaunchRequestArgv,
    iTermMultiServerTagLaunchRequestEnvironment,
    iTermMultiServerTagLaunchRequestColumns,
    iTermMultiServerTagLaunchRequestRows,
    iTermMultiServerTagLaunchRequestPixelWidth,
    iTermMultiServerTagLaunchRequestPixelHeight,
    iTermMultiServerTagLaunchRequestIsUTF8,
    iTermMultiServerTagLaunchRequestPwd,
    iTermMultiServerTagLaunchRequestUniqueId,

    iTermMultiServerTagWaitRequestPid,
    iTermMultiServerTagWaitRequestRemovePreemptively,

    iTermMultiServerTagWaitResponsePid,
    iTermMultiServerTagWaitResponseStatus,
    iTermMultiServerTagWaitResponseErrno,

    iTermMultiServerTagLaunchResponseStatus,
    iTermMultiServerTagLaunchResponsePid,
    iTermMultiServerTagLaunchResponseUniqueID,
    iTermMultiServerTagLaunchResponseTty,

    iTermMultiServerTagReportChildIsLast,
    iTermMultiServerTagReportChildPid,
    iTermMultiServerTagReportChildPath,
    iTermMultiServerTagReportChildArgs,
    iTermMultiServerTagReportChildEnv,
    iTermMultiServerTagReportChildPwd,
    iTermMultiServerTagReportChildIsUTF8,
    iTermMultiServerTagReportChildTerminated,
    iTermMultiServerTagReportChildTTY,

    iTermMultiServerTagTerminationPid,
    iTermMultiServerTagTerminationStatus,
} iTermMultiServerTagLaunch;

typedef struct {
    // iTermMultiServerTagHandshakeRequestClientMaximumProtocolVersion
    int maximumProtocolVersion;
} iTermMultiServerRequestHandshake;

typedef struct {
    // iTermMultiServerTagHandshakeResponseProtocolVersion
    int protocolVersion;

    // iTermMultiServerTagHandshakeResponseChildReportsNumChildren
    int numChildren;

    // iTermMultiServerTagHandshakeResponseProcessID
    int pid;
} iTermMultiServerResponseHandshake;

typedef struct {
    // iTermMultiServerTagLaunchRequestPath
    const char *path;

    // iTermMultiServerTagLaunchRequestArgv
    const char **argv;
    int argc;

    // iTermMultiServerTagLaunchRequestEnvironment
    const char **envp;
    int envc;

    // iTermMultiServerTagLaunchRequestColumns
    int columns;

    // iTermMultiServerTagLaunchRequestRows
    int rows;

    // iTermMultiServerTagLaunchRequestPixelWidth
    int pixel_width;

    // iTermMultiServerTagLaunchRequestPixelHeight
    int pixel_height;

    // iTermMultiServerTagLaunchRequestIsUTF8
    int isUTF8;

    // iTermMultiServerTagLaunchRequestPwd
    const char *pwd;

    // iTermMultiServerTagLaunchRequestUniqueId
    long long uniqueId;
} iTermMultiServerRequestLaunch;

// NOTE: The PTY master file descriptor is also passed with this message.
typedef struct {
    // 0 means success. Otherwise, gives errno from fork or execve.
    // iTermMultiServerTagLaunchResponseStatus
    int status;

    // Only defined if status is 0.
    // iTermMultiServerTagLaunchResponsePid
    pid_t pid;

    // File descriptor. Passed out of band.
    int fd;

    // iTermMultiServerTagLaunchResponseUniqueID
    long long uniqueId;

    // iTermMultiServerTagLaunchResponseTty
    const char *tty;
} iTermMultiServerResponseLaunch;

typedef struct {
    // iTermMultiServerTagWaitRequestPid
    pid_t pid;

    // iTermMultiServerTagWaitRequestRemovePreemptively
    int removePreemptively;
} iTermMultiServerRequestWait;

typedef struct {
    // iTermMultiServerTagWaitResponsePid
    pid_t pid;

    // iTermMultiServerTagWaitResponseStatus
    // Meaningful only if errorNumber is 0. Gives exit status from waitpid().
    int status;

    // iTermMultiServerTagWaitResponseErrno
    // 1: Child marked as future termination for preemptive wait.
    // 0: No error. Status is valid. Child has been removed.
    // -1: No such child
    // -2: Child not terminated
    int errorNumber;
} iTermMultiServerResponseWait;

typedef struct iTermMultiServerReportChild {
    // iTermMultiServerTagReportChildIsLast
    int isLast;

    // iTermMultiServerTagReportChildPid
    pid_t pid;

    // iTermMultiServerTagReportChildPath
    const char *path;

    // iTermMultiServerTagReportChildArgs
    const char **argv;
    int argc;

    // iTermMultiServerTagReportChildEnv
    const char **envp;
    int envc;

    // iTermMultiServerTagReportChildIsUTF8
    int isUTF8;

    // iTermMultiServerTagReportChildPwd
    const char *pwd;

    // iTermMultiServerTagReportChildTerminated
    int terminated;  // you should send iTermMultiServerResponseWait

    // iTermMultiServerTagReportChildTTY
    const char *tty;

    // Sent out-of-band
    int fd;
} iTermMultiServerReportChild;

typedef enum {
    iTermMultiServerRPCTypeHandshake,  // Client-originated, has response
    iTermMultiServerRPCTypeLaunch,  // Client-originated, has response
    iTermMultiServerRPCTypeWait,  // Client-originated, has response
    iTermMultiServerRPCTypeReportChild,  // Server-originated, no response.
    iTermMultiServerRPCTypeTermination  // Server-originated, no response.
} iTermMultiServerRPCType;

// You should send iTermMultiServerResponseWait after getting this.
typedef struct {
    // iTermMultiServerTagTerminationPid
    pid_t pid;
} iTermMultiServerReportTermination;

typedef struct {
    iTermMultiServerRPCType type;
    union {
        iTermMultiServerRequestHandshake handshake;
        iTermMultiServerRequestLaunch launch;
        iTermMultiServerRequestWait wait;
    } payload;
} iTermMultiServerClientOriginatedMessage;

typedef struct {
    iTermMultiServerRPCType type;
    union {
        iTermMultiServerResponseHandshake handshake;
        iTermMultiServerResponseLaunch launch;
        iTermMultiServerResponseWait wait;
        iTermMultiServerReportTermination termination;
        iTermMultiServerReportChild reportChild;
    } payload;
} iTermMultiServerServerOriginatedMessage;

int __attribute__((warn_unused_result))
iTermMultiServerProtocolParseMessageFromClient(iTermClientServerProtocolMessage *message,
                                               iTermMultiServerClientOriginatedMessage *out);

int __attribute__((warn_unused_result))
iTermMultiServerProtocolEncodeMessageFromClient(iTermMultiServerClientOriginatedMessage *obj,
                                                iTermClientServerProtocolMessage *message);

int __attribute__((warn_unused_result))
iTermMultiServerProtocolParseMessageFromServer(iTermClientServerProtocolMessage *message,
                                               iTermMultiServerServerOriginatedMessage *out);

int __attribute__((warn_unused_result))
iTermMultiServerProtocolEncodeMessageFromServer(iTermMultiServerServerOriginatedMessage *obj,
                                                iTermClientServerProtocolMessage *message);

void iTermMultiServerClientOriginatedMessageFree(iTermMultiServerClientOriginatedMessage *obj);
void iTermMultiServerServerOriginatedMessageFree(iTermMultiServerServerOriginatedMessage *obj);

// Reads a message from the UDS. Returns 0 on success. When successful, the message
// must be freed by the caller with iTermClientServerProtocolMessageFree().
int __attribute__((warn_unused_result))
iTermMultiServerRecv(int fd, iTermClientServerProtocolMessage *message);

// Reads text from a file descriptor.
int __attribute__((warn_unused_result))
iTermMultiServerRead(int fd, iTermClientServerProtocolMessage *message);

// Get a file descriptor from a received message. Returns nonzero on error. On success,
// sets *receivedFileDescriptorPtr to the file derscriptor you now own.
int __attribute__((warn_unused_result))
iTermMultiServerProtocolGetFileDescriptor(iTermClientServerProtocolMessage *message,
                                          int *receivedFileDescriptorPtr);
