//
//  main.m
//  serverdriver
//
//  Created by George Nachman on 11/1/20.
//

#import <Foundation/Foundation.h>
#include <sys/time.h>
BOOL gDebugLogging=1;
int DebugLogImpl(const char *file, int line, const char *function, NSString* value)
{
    struct timeval tv;
    gettimeofday(&tv, NULL);

    NSString *formatted = [NSString stringWithFormat:@"%lld.%06lld: %@",
                           (long long)tv.tv_sec, (long long)tv.tv_usec, value];
    printf("%s\n", formatted.UTF8String);
    return 1;
}
void DLogC(const char *format, va_list args) {
    char *temp = NULL;
    vasprintf(&temp, format, args);
    DebugLogImpl(NULL, 0, NULL, [NSString stringWithUTF8String:temp]);
    free(temp);
}
#import "iTermMultiServerProtocol.h"
#import "iTermClientServerProtocol.h"
#include <sys/select.h>
#include <sys/un.h>
#include <sys/socket.h>


typedef NS_ENUM(NSUInteger, iTermFileDescriptorMultiClientAttachStatus) {
    iTermFileDescriptorMultiClientAttachStatusSuccess,
    iTermFileDescriptorMultiClientAttachStatusConnectFailed,
    iTermFileDescriptorMultiClientAttachStatusFatalError,  // includes rejection, unexpected errors
    iTermFileDescriptorMultiClientAttachStatusInProgress  // connecting asynchronously
};

static iTermFileDescriptorMultiClientAttachStatus iTermConnectToUnixDomainSocket(NSString *pathString,
                                                                                 int *fdOut,
                                                                                 int async) {
    int interrupted = 0;
    int socketFd;
    int flags;

    const char *path = pathString.UTF8String;
    DLog(@"Trying to connect to %s", path);
    do {
        struct sockaddr_un remote;
        if (strlen(path) + 1 > sizeof(remote.sun_path)) {
            DLog(@"Path is too long: %s", path);
            return iTermFileDescriptorMultiClientAttachStatusFatalError;
        }

        DLog(@"Calling socket()");
        socketFd = socket(AF_UNIX, SOCK_STREAM, 0);
        if (socketFd == -1) {
            DLog(@"Failed to create socket: %s\n", strerror(errno));
            return iTermFileDescriptorMultiClientAttachStatusFatalError;
        }
        remote.sun_family = AF_UNIX;
        strcpy(remote.sun_path, path);
        const socklen_t len = (socklen_t)(strlen(remote.sun_path) + sizeof(remote.sun_family) + 1);
        DLog(@"Calling fcntl() 1");
        flags = fcntl(socketFd, F_GETFL, 0);

        // Put the socket in nonblocking mode so connect can fail fast if another iTerm2 is connected
        // to this server.
        DLog(@"Calling fcntl() 2");
        fcntl(socketFd, F_SETFL, flags | O_NONBLOCK);

        DLog(@"Calling connect()");
        int rc = connect(socketFd, (struct sockaddr *)&remote, len);
        if (rc == -1) {
            if (errno == EINPROGRESS) {
                if (async) {
                    *fdOut = socketFd;
                    return iTermFileDescriptorMultiClientAttachStatusInProgress;
                }
                // per connect(2): EINPROGRESS means the connection cannot be completed
                // immediately, and you should select for writing to wait for completion.
                // See also: https://cr.yp.to/docs/connect.html
                int fds[1] = { socketFd };
                int results[1] = { 0 };
                iTermSelectForWriting(fds, 1, results, 0);
                *fdOut = socketFd;
                return iTermFileDescriptorMultiClientAttachStatusSuccess;
            }
            interrupted = (errno == EINTR);
            DLog(@"Connect failed: %s\n", strerror(errno));
            close(socketFd);
            if (!interrupted) {
                return iTermFileDescriptorMultiClientAttachStatusConnectFailed;
            }
            DLog(@"Trying again because connect returned EINTR.");
        } else {
            interrupted = 0;
        }
    } while (interrupted);
    *fdOut = socketFd;
    return iTermFileDescriptorMultiClientAttachStatusSuccess;
}

iTermClientServerProtocolMessage ReadMessage(int fd) {
    // First read number of bytes
    size_t length;
    {
        iTermClientServerProtocolMessage message;
        ssize_t bytesRead = iTermMultiServerReadMessage(fd, &message, sizeof(size_t));
        assert(bytesRead == sizeof(size_t));
        memmove(&length, message.ioVectors[0].iov_base, sizeof(length));
        DLog(@"Size of message will be %d", (int)length);
    }

    // Now payload message
    iTermClientServerProtocolMessage result = { 0 };
    result.ioVectors[0].iov_base = NULL;
    result.ioVectors[0].iov_len = 0;
    while (length > 0) {
        iTermClientServerProtocolMessage message;
        ssize_t bytesRead = iTermMultiServerReadMessage(fd, &message, length);
        if (bytesRead <= 0) {
            DLog(@"Error or eof: %d (%s)", (int)bytesRead, strerror(errno));
            exit(1);
        }
        length -= bytesRead;
        DLog(@"Read returned %d, %d remain", (int)bytesRead, (int)length);
        if (result.ioVectors[0].iov_base == NULL) {
            result.ioVectors[0].iov_base = malloc(length);
            result.valid = 1;
            result.message = message.message;
            result.controlBuffer = message.controlBuffer;
            result.ioVectors[0].iov_base = malloc(message.ioVectors[0].iov_len);
            result.ioVectors[0].iov_len = message.ioVectors[0].iov_len;
            memmove(result.ioVectors[0].iov_base, message.ioVectors[0].iov_base, message.ioVectors[0].iov_len);
        } else {
            result.ioVectors[0].iov_base = realloc(result.ioVectors[0].iov_base, result.ioVectors[0].iov_len + message.ioVectors[0].iov_len);
            memmove(result.ioVectors[0].iov_base + result.ioVectors[0].iov_len,
                    message.ioVectors[0].iov_base,
                    message.ioVectors[0].iov_len);
            result.ioVectors[0].iov_len += message.ioVectors[0].iov_len;
        }
    }
    return result;
}

//iTermClientServerProtocolMessage *ReadBytes(int fd, size_t *lengthOut, int *fdOut) {
//    iTermClientServerProtocolMessage message = ReadMessage(fd);
//    if (message.controlBuffer.cm.cmsg_len == CMSG_LEN(sizeof(int)) &&
//        message.controlBuffer.cm.cmsg_level == SOL_SOCKET &&
//        message.controlBuffer.cm.cmsg_type == SCM_RIGHTS) {
//        DLog(@"Got a file descriptor in message");
//        *fdOut = *((int *)CMSG_DATA(&message.controlBuffer.cm));
//    } else {
//        *fdOut = -1;
//    }
//
//    char *buffer = malloc(length);
//    memmove(buffer, message.ioVectors[0].iov_base, length);
//    return buffer;
//}
//
iTermMultiServerServerOriginatedMessage ReadAndParseMessage(int fd, int *fdOut) {
    iTermClientServerProtocolMessage message = ReadMessage(fd);

    if (message.controlBuffer.cm.cmsg_len == CMSG_LEN(sizeof(int)) &&
        message.controlBuffer.cm.cmsg_level == SOL_SOCKET &&
        message.controlBuffer.cm.cmsg_type == SCM_RIGHTS) {
        DLog(@"Got a file descriptor in message");
        *fdOut = *((int *)CMSG_DATA(&message.controlBuffer.cm));
    } else {
        *fdOut = -1;
    }

    iTermMultiServerServerOriginatedMessage decodedMessage;
    const int status = iTermMultiServerProtocolParseMessageFromServer(&message, &decodedMessage);
    if (status) {
        DLog(@"Failed to decode message from server with status %d", status);
        exit(1);
    }
    iTermMultiServerProtocolLogMessageFromServer(&decodedMessage);
    return decodedMessage;
}

int WriteMessage(int writefd, iTermMultiServerClientOriginatedMessage *messagePtr) {
    iTermClientServerProtocolMessage clientServerProtocolMessage;
    iTermClientServerProtocolMessageInitialize(&clientServerProtocolMessage);
    if (iTermMultiServerProtocolEncodeMessageFromClient(messagePtr, &clientServerProtocolMessage)) {
        DLog(@"Failed to encode message from client");
        iTermMultiServerProtocolLogMessageFromClient(messagePtr);
        return 1;
    }
    const size_t length = clientServerProtocolMessage.ioVectors[0].iov_len;

    // Write length
    {
        ssize_t bytesWritten = iTermFileDescriptorClientWrite(writefd,
                                                              &length,
                                                              sizeof(length));
        if (bytesWritten != sizeof(length)) {
            return 1;
        }
    }


    char *buffer = malloc(length);
    memmove(buffer, clientServerProtocolMessage.ioVectors[0].iov_base, length);
    ssize_t bytesWritten = iTermFileDescriptorClientWrite(writefd,
                                                          clientServerProtocolMessage.ioVectors[0].iov_base,
                                                          length);
    if (bytesWritten != length) {
        return 1;
    }
    DLog(@"Sent.");
    return 0;
}

int Run(const char *path) {
    @autoreleasepool {
        int fd;
        iTermFileDescriptorMultiClientAttachStatus status = iTermConnectToUnixDomainSocket([NSString stringWithUTF8String:path], &fd, 0);
        if (status != iTermFileDescriptorMultiClientAttachStatusSuccess) {
            printf("Connect failed\n");
            return 1;
        }

        int flags = fcntl(fd, F_GETFL, 0);
        fcntl(fd, F_SETFL, flags & ~O_NONBLOCK);

        DLog(@"Get write fd");
        iTermMultiServerServerOriginatedMessage message;
        int writefd = -1;
        message = ReadAndParseMessage(fd, &writefd);
        assert(writefd != -1);

        {
            DLog(@"Sending handshake request");
            iTermMultiServerClientOriginatedMessage handshakeRequest = {
                .type = iTermMultiServerRPCTypeHandshake,
                .payload = {
                    .handshake = {
                        .maximumProtocolVersion = iTermMultiServerProtocolVersion2
                    }
                }
            };
            if (WriteMessage(writefd, &handshakeRequest)) {
                DLog(@"write handshake failed");
                return 1;
            }

            DLog(@"Read handshake response");
            int ignore=-1;
            message = ReadAndParseMessage(fd, &ignore);
            assert(message.type == iTermMultiServerRPCTypeHandshake);
            DLog(@"Have %d children to read", message.payload.handshake.numChildren);
            int numChildren = message.payload.handshake.numChildren;
            for (int i = 0; i < numChildren; i++) {
                message = ReadAndParseMessage(fd, &ignore);
                assert(message.type == iTermMultiServerRPCTypeReportChild);
                DLog(@"Read child report %d", i);
            }
        }

        DLog(@"Launch child");
        const char *argv[] = {"/bin/bash", NULL};
        const char *envp[] = {"", NULL};
        iTermMultiServerClientOriginatedMessage launchRequest = {
            .type = iTermMultiServerRPCTypeLaunch,
            .payload = {
                .launch = {
                    .path = "/bin/bash",
                    .argv = argv,
                    .argc = 1,
                    .envp = envp,
                    .columns = 80,
                    .rows = 25,
                    .pixel_width = 800,
                    .pixel_height = 250,
                    .isUTF8 = 1,
                    .pwd = "/",
                    .uniqueId = 1234
                }
            }
        };
        if (WriteMessage(writefd, &launchRequest)) {
            DLog(@"write launch request failed");
            return 1;
        }
        DLog(@"Launch request sent");

        DLog(@"Read launch response");
        int pty = -1;
        message = ReadAndParseMessage(fd, &pty);
        assert(message.type == iTermMultiServerRPCTypeLaunch);
        DLog(@"pid = %d, status = %d, pty=%d", message.payload.launch.pid, message.payload.launch.status, pty);

        flags = fcntl(pty, F_GETFL, 0);
        fcntl(pty, F_SETFL, flags & ~O_NONBLOCK);
        DLog(@"Read from child FD");
        while (1) {
            char buffer[1024];
            ssize_t rc = read(pty, buffer, sizeof(buffer));
            if (rc < 0) {
                DLog(@"\nread failed: %s", strerror(errno));
                return 1;
            }
            if (rc == 0) {
                DLog(@"\nEOF\n");
                return 0;
            }
            DLog(@"%.*s", (int)rc, buffer);
        }
    }
    return 0;
}

int main(int argc, const char * argv[]) {
    if (argc != 2) {
        printf("Usage: %s path-to-socket\n", argv[0]);
    }
    return Run(argv[1]);
}
