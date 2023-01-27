//
//  iTermMultiServerProtocol.h
//  iTerm2
//
//  Created by George Nachman on 7/25/19.
//

#import "iTermClientServerProtocol.h"

enum {
    iTermMultiServerProtocolVersionRejected = -1,
    iTermMultiServerProtocolVersion1 = 1,
    iTermMultiServerProtocolVersion2 = 2
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
    iTermMultiServerTagWaitResponseResultType,

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
    unsigned long long uniqueId;
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
    unsigned long long uniqueId;

    // iTermMultiServerTagLaunchResponseTty
    const char *tty;
} iTermMultiServerResponseLaunch;

typedef struct {
    // iTermMultiServerTagWaitRequestPid
    pid_t pid;

    // iTermMultiServerTagWaitRequestRemovePreemptively
    int removePreemptively;
} iTermMultiServerRequestWait;

// A note on preemptive wait: we use this when we kill the child with a signal.
// The server doesn't remove its reference to the child immediately, but the
// client does. That's because the client is unilaterally breaking ties with
// this child. If for some reason it does not die, the server is responsible
// for wait()ing on it eventually. So it is possible that they will get out of
// sync. This will be resolved on the next attach, when that child will come
// back as an orphan.
typedef int iTermMultiServerResponseWaitResultType;
enum iTermMultiServerResponseWaitResultType {
    iTermMultiServerResponseWaitResultTypePreemptive = 1,  // Child marked as future termination for preemptive wait.
    iTermMultiServerResponseWaitResultTypeStatusIsValid = 0,  // No error. Status is valid. Child has been removed.
    iTermMultiServerResponseWaitResultTypeNoSuchChild = -1,  // No such child
    iTermMultiServerResponseWaitResultTypeNotTerminated = -2,  // Child not terminated
};

typedef struct {
    // iTermMultiServerTagWaitResponsePid
    pid_t pid;

    // iTermMultiServerTagWaitResponseStatus
    // Meaningful only if resultType is .statusIsValid. Gives exit status from waitpid().
    int status;

    // iTermMultiServerTagWaitResponseResultType
    iTermMultiServerResponseWaitResultType resultType;
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
    iTermMultiServerRPCTypeTermination,  // Server-originated, no response.
    iTermMultiServerRPCTypeHello,  // Server-originated, no response.
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
} iTermMultiServerHello;

typedef struct {
    iTermMultiServerRPCType type;
    union {
        iTermMultiServerResponseHandshake handshake;
        iTermMultiServerResponseLaunch launch;
        iTermMultiServerResponseWait wait;
        iTermMultiServerReportTermination termination;
        iTermMultiServerReportChild reportChild;
        iTermMultiServerHello hello;
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

// Reads a message from the UDS. Returns -1 on error or number of bytes read on success.
// When successful, the message must be freed by the caller with
// iTermClientServerProtocolMessageFree().
// NOTE: a status of 0 is not EOF! You could have zero bytes and a file descriptor, and it would
// return 0.
ssize_t __attribute__((warn_unused_result))
iTermMultiServerReadMessage(int fd, iTermClientServerProtocolMessage *message, ssize_t bufferSize);

// Reads text from a file descriptor.
int __attribute__((warn_unused_result))
iTermMultiServerRead(int fd, iTermClientServerProtocolMessage *message);

// Get a file descriptor from a received message. Returns nonzero on error. On success,
// sets *receivedFileDescriptorPtr to the file derscriptor you now own.
int __attribute__((warn_unused_result))
iTermMultiServerProtocolGetFileDescriptor(iTermClientServerProtocolMessage *message,
                                          int *receivedFileDescriptorPtr);

void
iTermMultiServerProtocolLogMessageFromClient(iTermMultiServerClientOriginatedMessage *message);

typedef void iTermMultiServerProtocolLogFunction(const char *file, int line, const char *func, const char *format, ...);

void
iTermMultiServerProtocolLogMessageFromClient(iTermMultiServerClientOriginatedMessage *message);

void
iTermMultiServerProtocolLogMessageFromServer(iTermMultiServerServerOriginatedMessage *message);

void
iTermMultiServerProtocolLogMessageFromClient2(iTermMultiServerClientOriginatedMessage *message,
                                              iTermMultiServerProtocolLogFunction logFunction);

void
iTermMultiServerProtocolLogMessageFromServer2(iTermMultiServerServerOriginatedMessage *message,
                                              iTermMultiServerProtocolLogFunction logFunction);
