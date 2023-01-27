//
//  iTermMultiServerProtocol.c
//  iTerm2
//
//  Created by George Nachman on 7/25/19.
//

#import "iTermMultiServerProtocol.h"

#include "DebugLogging.h"

#include <assert.h>
#include <errno.h>
#include <stdlib.h>
#include <string.h>
#include <sys/types.h>
#include <sys/uio.h>
#include <unistd.h>

#define LogToLogFunc(args...) logFunction(__FILE__, __LINE__, __FUNCTION__, args)

typedef enum iTermMultiServerProtocolError {
    iTermMultiServerProtocolErrorEncodingFailed = -1,

    iTermMultiServerProtocolErrorMissingType = 1,
    iTermMultiServerProtocolErrorUnknownType = 2,
    iTermMultiServerProtocolErrorUnexpectedType = 3,
    iTermMultiServerProtocolErrorMissingFileDescriptor = 4,
    iTermMultiServerProtocolErrorBrokenHeader = 5,

    iTermMultiServerProtocolErrorHandshakeRequestMissingVersion = 100,

    iTermMultiServerProtocolErrorHandshakeResponseMissingVersion = 200,
    iTermMultiServerProtocolErrorHandshakeResponseMissingNumChildren = 201,
    iTermMultiServerProtocolErrorHandshakeResponseMissingProcessID = 202,
    iTermMultiServerProtocolErrorHandshakeResponseInvalidNumberOfChildren = 203,

    iTermMultiServerProtocolErrorLaunchRequestMissingPath = 300,
    iTermMultiServerProtocolErrorLaunchRequestMissingArgv = 301,
    iTermMultiServerProtocolErrorLaunchRequestMissingEnviron = 302,
    iTermMultiServerProtocolErrorLaunchRequestMissingColumns = 303,
    iTermMultiServerProtocolErrorLaunchRequestMissingRows = 304,
    iTermMultiServerProtocolErrorLaunchRequestMissingPixelWidth = 305,
    iTermMultiServerProtocolErrorLaunchRequestMissingPixelHeight = 306,
    iTermMultiServerProtocolErrorLaunchRequestMissingUTF8 = 307,
    iTermMultiServerProtocolErrorLaunchRequestMissingPWD = 308,
    iTermMultiServerProtocolErrorLaunchRequestMissingUniqueID = 309,

    iTermMultiServerProtocolErrorLaunchResponseMissingStatus = 400,
    iTermMultiServerProtocolErrorLaunchResponseMissingPID = 401,
    iTermMultiServerProtocolErrorLaunchResponseMissingUniqueID = 402,
    iTermMultiServerProtocolErrorLaunchResponseMissingTTY = 403,

    iTermMultiServerProtocolErrorWaitRequestMissingPID = 500,
    iTermMultiServerProtocolErrorWaitRequestMissingRemovePreemptively = 501,

    iTermMultiServerProtocolErrorWaitResponseMissingPID = 600,
    iTermMultiServerProtocolErrorWaitResponseMissingStatus = 601,
    iTermMultiServerProtocolErrorWaitResponseMissingErrno = 602,

    iTermMultiServerProtocolErrorReportChildMissingIsLast = 700,
    iTermMultiServerProtocolErrorReportChildMissingPID = 701,
    iTermMultiServerProtocolErrorReportChildMissingPath = 702,
    iTermMultiServerProtocolErrorReportChildMissingArgs = 703,
    iTermMultiServerProtocolErrorReportChildMissingEnviron = 704,
    iTermMultiServerProtocolErrorReportChildMissingIsUTF8 = 705,
    iTermMultiServerProtocolErrorReportChildMissingPWD = 706,
    iTermMultiServerProtocolErrorReportChildMissingTerminated = 707,
    iTermMultiServerProtocolErrorReportChildMissingTTY = 708,

    iTermMultiServerProtocolErrorTerminationMissingPID = 800,
} iTermMultiServerProtocolError;

static int ParseHandshakeRequest(iTermClientServerProtocolMessageParser *parser,
                                 iTermMultiServerRequestHandshake *out) {
    if (iTermClientServerProtocolParseTaggedInt(parser, &out->maximumProtocolVersion, sizeof(out->maximumProtocolVersion), iTermMultiServerTagHandshakeRequestClientMaximumProtocolVersion)) {
        return iTermMultiServerProtocolErrorHandshakeRequestMissingVersion;
    }
    return 0;
}

static int EncodeHandshakeRequest(iTermClientServerProtocolMessageEncoder *encoder,
                                  iTermMultiServerRequestHandshake *handshake) {
    if (iTermClientServerProtocolEncodeTaggedInt(encoder, &handshake->maximumProtocolVersion, sizeof(handshake->maximumProtocolVersion), iTermMultiServerTagHandshakeRequestClientMaximumProtocolVersion)) {
        return iTermMultiServerProtocolErrorEncodingFailed;
    }
    return 0;
}

static int ParseHandshakeResponse(iTermClientServerProtocolMessageParser *parser,
                                  iTermMultiServerResponseHandshake *out) {
    if (iTermClientServerProtocolParseTaggedInt(parser, &out->protocolVersion, sizeof(out->protocolVersion), iTermMultiServerTagHandshakeResponseProtocolVersion)) {
        return iTermMultiServerProtocolErrorHandshakeResponseMissingVersion;
    }
    if (iTermClientServerProtocolParseTaggedInt(parser, &out->numChildren, sizeof(out->numChildren), iTermMultiServerTagHandshakeResponseChildReportsNumChildren)) {
        return iTermMultiServerProtocolErrorHandshakeResponseMissingNumChildren;
    }
    if (iTermClientServerProtocolParseTaggedInt(parser, &out->pid, sizeof(out->pid), iTermMultiServerTagHandshakeResponseProcessID)) {
        return iTermMultiServerProtocolErrorHandshakeResponseMissingProcessID;
    }
    if (out->numChildren < 0 || out->numChildren > 1024) {
        return iTermMultiServerProtocolErrorHandshakeResponseInvalidNumberOfChildren;
    }
    return 0;
}

static int EncodeHandshakeResponse(iTermClientServerProtocolMessageEncoder *encoder,
                                   iTermMultiServerResponseHandshake *handshake) {
    if (iTermClientServerProtocolEncodeTaggedInt(encoder, &handshake->protocolVersion, sizeof(handshake->protocolVersion), iTermMultiServerTagHandshakeResponseProtocolVersion)) {
        return iTermMultiServerProtocolErrorEncodingFailed;
    }
    if (iTermClientServerProtocolEncodeTaggedInt(encoder, &handshake->numChildren, sizeof(handshake->numChildren), iTermMultiServerTagHandshakeResponseChildReportsNumChildren)) {
        return iTermMultiServerProtocolErrorEncodingFailed;
    }
    if (iTermClientServerProtocolEncodeTaggedInt(encoder, &handshake->pid, sizeof(handshake->pid), iTermMultiServerTagHandshakeResponseProcessID)) {
        return iTermMultiServerProtocolErrorEncodingFailed;
    }
    return 0;
}

static int ParseLaunchReqest(iTermClientServerProtocolMessageParser *parser,
                             iTermMultiServerRequestLaunch *out) {
    if (iTermClientServerProtocolParseTaggedString(parser, (char **)&out->path, iTermMultiServerTagLaunchRequestPath)) {
        return iTermMultiServerProtocolErrorLaunchRequestMissingPath;
    }
    if (iTermClientServerProtocolParseTaggedStringArray(parser, (char ***)&out->argv, &out->argc, iTermMultiServerTagLaunchRequestArgv)) {
        return iTermMultiServerProtocolErrorLaunchRequestMissingArgv;
    }
    if (iTermClientServerProtocolParseTaggedStringArray(parser, (char ***)&out->envp, &out->envc, iTermMultiServerTagLaunchRequestEnvironment)) {
        return iTermMultiServerProtocolErrorLaunchRequestMissingEnviron;
    }
    if (iTermClientServerProtocolParseTaggedInt(parser, &out->columns, sizeof(out->columns), iTermMultiServerTagLaunchRequestColumns)) {
        return iTermMultiServerProtocolErrorLaunchRequestMissingColumns;
    }
    if (iTermClientServerProtocolParseTaggedInt(parser, &out->rows, sizeof(out->rows), iTermMultiServerTagLaunchRequestRows)) {
        return iTermMultiServerProtocolErrorLaunchRequestMissingRows;
    }
    if (iTermClientServerProtocolParseTaggedInt(parser, &out->pixel_width, sizeof(out->pixel_width), iTermMultiServerTagLaunchRequestPixelWidth)) {
        return iTermMultiServerProtocolErrorLaunchRequestMissingPixelWidth;
    }
    if (iTermClientServerProtocolParseTaggedInt(parser, &out->pixel_height, sizeof(out->pixel_height), iTermMultiServerTagLaunchRequestPixelHeight)) {
        return iTermMultiServerProtocolErrorLaunchRequestMissingPixelHeight;
    }
    if (iTermClientServerProtocolParseTaggedInt(parser, &out->isUTF8, sizeof(out->isUTF8), iTermMultiServerTagLaunchRequestIsUTF8)) {
        return iTermMultiServerProtocolErrorLaunchRequestMissingUTF8;
    }
    if (iTermClientServerProtocolParseTaggedString(parser, (char **)&out->pwd, iTermMultiServerTagLaunchRequestPwd)) {
        return iTermMultiServerProtocolErrorLaunchRequestMissingPWD;
    }
    if (iTermClientServerProtocolParseTaggedInt(parser, &out->uniqueId, sizeof(out->uniqueId), iTermMultiServerTagLaunchRequestUniqueId)) {
        return iTermMultiServerProtocolErrorLaunchRequestMissingUniqueID;
    }
    return 0;
}

static int EncodeLaunchRequest(iTermClientServerProtocolMessageEncoder *encoder,
                               iTermMultiServerRequestLaunch *launch) {
    if (iTermClientServerProtocolEncodeTaggedString(encoder, launch->path, iTermMultiServerTagLaunchRequestPath)) {
        return iTermMultiServerProtocolErrorEncodingFailed;
    }
    if (iTermClientServerProtocolEncodeTaggedStringArray(encoder, (char **)launch->argv, launch->argc, iTermMultiServerTagLaunchRequestArgv)) {
        return iTermMultiServerProtocolErrorEncodingFailed;
    }
    if (iTermClientServerProtocolEncodeTaggedStringArray(encoder, (char **)launch->envp, launch->envc, iTermMultiServerTagLaunchRequestEnvironment)) {
        return iTermMultiServerProtocolErrorEncodingFailed;
    }
    if (iTermClientServerProtocolEncodeTaggedInt(encoder, &launch->columns, sizeof(launch->columns), iTermMultiServerTagLaunchRequestColumns)) {
        return iTermMultiServerProtocolErrorEncodingFailed;
    }
    if (iTermClientServerProtocolEncodeTaggedInt(encoder, &launch->rows, sizeof(launch->rows), iTermMultiServerTagLaunchRequestRows)) {
        return iTermMultiServerProtocolErrorEncodingFailed;
    }
    if (iTermClientServerProtocolEncodeTaggedInt(encoder, &launch->pixel_width, sizeof(launch->pixel_width), iTermMultiServerTagLaunchRequestPixelWidth)) {
        return iTermMultiServerProtocolErrorEncodingFailed;
    }
    if (iTermClientServerProtocolEncodeTaggedInt(encoder, &launch->pixel_height, sizeof(launch->pixel_height), iTermMultiServerTagLaunchRequestPixelHeight)) {
        return iTermMultiServerProtocolErrorEncodingFailed;
    }
    if (iTermClientServerProtocolEncodeTaggedInt(encoder, &launch->isUTF8, sizeof(launch->isUTF8), iTermMultiServerTagLaunchRequestIsUTF8)) {
        return iTermMultiServerProtocolErrorEncodingFailed;
    }
    if (iTermClientServerProtocolEncodeTaggedString(encoder, launch->pwd, iTermMultiServerTagLaunchRequestPwd)) {
        return iTermMultiServerProtocolErrorEncodingFailed;
    }
    if (iTermClientServerProtocolEncodeTaggedInt(encoder, &launch->uniqueId, sizeof(launch->uniqueId), iTermMultiServerTagLaunchRequestUniqueId)) {
        return iTermMultiServerProtocolErrorEncodingFailed;
    }
    return 0;
}

static int ParseLaunchResponse(iTermClientServerProtocolMessageParser *parser,
                               iTermMultiServerResponseLaunch *out) {
    if (iTermClientServerProtocolParseTaggedInt(parser, &out->status, sizeof(out->status), iTermMultiServerTagLaunchResponseStatus)) {
        return iTermMultiServerProtocolErrorLaunchResponseMissingStatus;
    }
    if (iTermClientServerProtocolParseTaggedInt(parser, &out->pid, sizeof(out->pid), iTermMultiServerTagLaunchResponsePid)) {
        return iTermMultiServerProtocolErrorLaunchResponseMissingPID;
    }
    if (iTermClientServerProtocolParseTaggedInt(parser, &out->uniqueId, sizeof(out->uniqueId), iTermMultiServerTagLaunchResponseUniqueID)) {
        return iTermMultiServerProtocolErrorLaunchResponseMissingUniqueID;
    }
    if (iTermClientServerProtocolParseTaggedString(parser, (char **)&out->tty, iTermMultiServerTagLaunchResponseTty)) {
        return iTermMultiServerProtocolErrorLaunchResponseMissingTTY;
    }
    return 0;
}

static int EncodeLaunchResponse(iTermClientServerProtocolMessageEncoder *encoder,
                                iTermMultiServerResponseLaunch *launch) {
    if (iTermClientServerProtocolEncodeTaggedInt(encoder, &launch->status, sizeof(launch->status), iTermMultiServerTagLaunchResponseStatus)) {
        return iTermMultiServerProtocolErrorEncodingFailed;
    }
    if (iTermClientServerProtocolEncodeTaggedInt(encoder, &launch->pid, sizeof(launch->pid), iTermMultiServerTagLaunchResponsePid)) {
        return iTermMultiServerProtocolErrorEncodingFailed;
    }
    if (iTermClientServerProtocolEncodeTaggedInt(encoder, &launch->uniqueId, sizeof(launch->uniqueId), iTermMultiServerTagLaunchResponseUniqueID)) {
        return iTermMultiServerProtocolErrorEncodingFailed;
    }
    if (iTermClientServerProtocolEncodeTaggedString(encoder, launch->tty, iTermMultiServerTagLaunchResponseTty)) {
        return iTermMultiServerProtocolErrorEncodingFailed;
    }
    return 0;
}

static int ParseWaitRequest(iTermClientServerProtocolMessageParser *parser,
                            iTermMultiServerRequestWait *out) {
    if (iTermClientServerProtocolParseTaggedInt(parser, &out->pid, sizeof(out->pid), iTermMultiServerTagWaitRequestPid)) {
        return iTermMultiServerProtocolErrorWaitRequestMissingPID;
    }
    if (iTermClientServerProtocolParseTaggedInt(parser, &out->removePreemptively, sizeof(out->removePreemptively), iTermMultiServerTagWaitRequestRemovePreemptively)) {
        return iTermMultiServerProtocolErrorWaitRequestMissingRemovePreemptively;
    }
    return 0;
}

static int EncodeWaitRequest(iTermClientServerProtocolMessageEncoder *encoder,
                             iTermMultiServerRequestWait *wait) {
    if (iTermClientServerProtocolEncodeTaggedInt(encoder, &wait->pid, sizeof(wait->pid), iTermMultiServerTagWaitRequestPid)) {
        return iTermMultiServerProtocolErrorEncodingFailed;
    }
    if (iTermClientServerProtocolEncodeTaggedInt(encoder, &wait->removePreemptively, sizeof(wait->removePreemptively), iTermMultiServerTagWaitRequestRemovePreemptively)) {
        return iTermMultiServerProtocolErrorEncodingFailed;
    }
    return 0;
}

static int ParseWaitResponse(iTermClientServerProtocolMessageParser *parser,
                             iTermMultiServerResponseWait *out) {
    if (iTermClientServerProtocolParseTaggedInt(parser, &out->pid, sizeof(out->pid), iTermMultiServerTagWaitResponsePid)) {
        return iTermMultiServerProtocolErrorWaitResponseMissingPID;
    }
    if (iTermClientServerProtocolParseTaggedInt(parser, &out->status, sizeof(out->status), iTermMultiServerTagWaitResponseStatus)) {
        return iTermMultiServerProtocolErrorWaitResponseMissingStatus;
    }
    if (iTermClientServerProtocolParseTaggedInt(parser, &out->resultType, sizeof(out->resultType), iTermMultiServerTagWaitResponseResultType)) {
        return iTermMultiServerProtocolErrorWaitResponseMissingErrno;
    }
    return 0;
}

static int EncodeWaitResponse(iTermClientServerProtocolMessageEncoder *encoder,
                              iTermMultiServerResponseWait *wait) {
    if (iTermClientServerProtocolEncodeTaggedInt(encoder, &wait->pid, sizeof(wait->pid), iTermMultiServerTagWaitResponsePid)) {
        return iTermMultiServerProtocolErrorEncodingFailed;
    }
    if (iTermClientServerProtocolEncodeTaggedInt(encoder, &wait->status, sizeof(wait->status), iTermMultiServerTagWaitResponseStatus)) {
        return iTermMultiServerProtocolErrorEncodingFailed;
    }
    if (iTermClientServerProtocolEncodeTaggedInt(encoder, &wait->resultType, sizeof(wait->resultType), iTermMultiServerTagWaitResponseResultType)) {
        return iTermMultiServerProtocolErrorEncodingFailed;
    }
    return 0;
}

static int ParseReportChild(iTermClientServerProtocolMessageParser *parser,
                            iTermMultiServerReportChild *out) {
    if (iTermClientServerProtocolParseTaggedInt(parser, &out->isLast, sizeof(out->isLast), iTermMultiServerTagReportChildIsLast)) {
        return iTermMultiServerProtocolErrorReportChildMissingIsLast;
    }
    if (iTermClientServerProtocolParseTaggedInt(parser, &out->pid, sizeof(out->pid), iTermMultiServerTagReportChildPid)) {
        return iTermMultiServerProtocolErrorReportChildMissingPID;
    }
    if (iTermClientServerProtocolParseTaggedString(parser, (char **)&out->path, iTermMultiServerTagReportChildPath)) {
        return iTermMultiServerProtocolErrorReportChildMissingPath;
    }
    if (iTermClientServerProtocolParseTaggedStringArray(parser, (char ***)&out->argv, &out->argc, iTermMultiServerTagReportChildArgs)) {
        return iTermMultiServerProtocolErrorReportChildMissingArgs;
    }
    if (iTermClientServerProtocolParseTaggedStringArray(parser, (char ***)&out->envp, &out->envc, iTermMultiServerTagReportChildEnv)) {
        return iTermMultiServerProtocolErrorReportChildMissingEnviron;
    }
    if (iTermClientServerProtocolParseTaggedInt(parser, &out->isUTF8, sizeof(out->isUTF8), iTermMultiServerTagReportChildIsUTF8)) {
        return iTermMultiServerProtocolErrorReportChildMissingIsUTF8;
    }
    if (iTermClientServerProtocolParseTaggedString(parser, (char **)&out->pwd, iTermMultiServerTagReportChildPwd)) {
        return iTermMultiServerProtocolErrorReportChildMissingPWD;
    }
    if (iTermClientServerProtocolParseTaggedInt(parser, &out->terminated, sizeof(out->terminated), iTermMultiServerTagReportChildTerminated)) {
        return iTermMultiServerProtocolErrorReportChildMissingTerminated;
    }
    if (iTermClientServerProtocolParseTaggedString(parser, (char **)&out->tty, iTermMultiServerTagReportChildTTY)) {
        return iTermMultiServerProtocolErrorReportChildMissingTTY;
    }
    return 0;
}

static int EncodeReportChild(iTermClientServerProtocolMessageEncoder *encoder,
                             iTermMultiServerReportChild *obj) {
    if (iTermClientServerProtocolEncodeTaggedInt(encoder, &obj->isLast, sizeof(obj->isLast), iTermMultiServerTagReportChildIsLast)) {
        return iTermMultiServerProtocolErrorEncodingFailed;
    }
    if (iTermClientServerProtocolEncodeTaggedInt(encoder, &obj->pid, sizeof(obj->pid), iTermMultiServerTagReportChildPid)) {
        return iTermMultiServerProtocolErrorEncodingFailed;
    }
    if (iTermClientServerProtocolEncodeTaggedString(encoder, obj->path, iTermMultiServerTagReportChildPath)) {
        return iTermMultiServerProtocolErrorEncodingFailed;
    }
    if (iTermClientServerProtocolEncodeTaggedStringArray(encoder, (char **)obj->argv, obj->argc, iTermMultiServerTagReportChildArgs)) {
        return iTermMultiServerProtocolErrorEncodingFailed;
    }
    if (iTermClientServerProtocolEncodeTaggedStringArray(encoder, (char **)obj->envp, obj->envc, iTermMultiServerTagReportChildEnv)) {
        return iTermMultiServerProtocolErrorEncodingFailed;
    }
    if (iTermClientServerProtocolEncodeTaggedInt(encoder, &obj->isUTF8, sizeof(obj->isUTF8), iTermMultiServerTagReportChildIsUTF8)) {
        return iTermMultiServerProtocolErrorEncodingFailed;
    }
    if (iTermClientServerProtocolEncodeTaggedString(encoder, obj->pwd, iTermMultiServerTagReportChildPwd)) {
        return iTermMultiServerProtocolErrorEncodingFailed;
    }
    if (iTermClientServerProtocolEncodeTaggedInt(encoder, &obj->terminated, sizeof(obj->terminated), iTermMultiServerTagReportChildTerminated)) {
        return iTermMultiServerProtocolErrorEncodingFailed;
    }
    if (iTermClientServerProtocolEncodeTaggedString(encoder, obj->tty, iTermMultiServerTagReportChildTTY)) {
        return iTermMultiServerProtocolErrorEncodingFailed;
    }
    return 0;
}

static int ParseTermination(iTermClientServerProtocolMessageParser *parser,
                            iTermMultiServerReportTermination *out) {
    if (iTermClientServerProtocolParseTaggedInt(parser, &out->pid, sizeof(out->pid), iTermMultiServerTagTerminationPid)) {
        return iTermMultiServerProtocolErrorTerminationMissingPID;
    }
    return 0;
}

static int EncodeTermination(iTermClientServerProtocolMessageEncoder *encoder,
                             iTermMultiServerReportTermination *obj) {
    if (iTermClientServerProtocolEncodeTaggedInt(encoder, &obj->pid, sizeof(obj->pid), iTermMultiServerTagTerminationPid)) {
        return iTermMultiServerProtocolErrorEncodingFailed;
    }
    return 0;
}

static int EncodeHello(iTermClientServerProtocolMessageEncoder *encoder,
                       iTermMultiServerHello *obj) {
    return 0;
}

static int ParseHello(iTermClientServerProtocolMessageParser *parser,
                      iTermMultiServerHello *out) {
    return 0;
}

#pragma mark - APIs

int iTermMultiServerProtocolParseMessageFromClient(iTermClientServerProtocolMessage *message,
                                                   iTermMultiServerClientOriginatedMessage *out) {
    memset(out, 0, sizeof(*out));
    iTermClientServerProtocolMessageParser parser = {
        .offset = 0,
        .message = message
    };

    if (iTermClientServerProtocolParseTaggedInt(&parser, &out->type, sizeof(out->type), iTermMultiServerTagType)) {
        return iTermMultiServerProtocolErrorMissingType;
    }
    switch (out->type) {
        case iTermMultiServerRPCTypeHandshake:
            return ParseHandshakeRequest(&parser, &out->payload.handshake);
        case iTermMultiServerRPCTypeLaunch:
            return ParseLaunchReqest(&parser, &out->payload.launch);
        case iTermMultiServerRPCTypeWait:
            return ParseWaitRequest(&parser, &out->payload.wait);

        case iTermMultiServerRPCTypeReportChild:  // Server-originated, no response.
        case iTermMultiServerRPCTypeTermination: // Server-originated, no response.
        case iTermMultiServerRPCTypeHello: // Server-originated, no response.
            return iTermMultiServerProtocolErrorUnexpectedType;
    }
    FDLog(LOG_DEBUG, "Parsed message with unknown type %d", (int)out->type);
    return iTermMultiServerProtocolErrorUnknownType;
}

int iTermMultiServerProtocolGetFileDescriptor(iTermClientServerProtocolMessage *message,
                                              int *receivedFileDescriptorPtr) {
    // Should be this:
//    struct cmsghdr *messageHeader = CMSG_FIRSTHDR(&message->message);
    // But because the structure is copied you can't trust the pointer.
    struct cmsghdr *messageHeader = &message->controlBuffer.cm;
    if (messageHeader->cmsg_len != CMSG_LEN(sizeof(int))) {
        return iTermMultiServerProtocolErrorMissingFileDescriptor;
    }
    if (messageHeader->cmsg_level != SOL_SOCKET) {
        return iTermMultiServerProtocolErrorBrokenHeader;
    }
    if (messageHeader->cmsg_type != SCM_RIGHTS) {
        return iTermMultiServerProtocolErrorBrokenHeader;
    }
    *receivedFileDescriptorPtr = *((int *)CMSG_DATA(messageHeader));
    return 0;
}

int iTermMultiServerProtocolParseMessageFromServer(iTermClientServerProtocolMessage *message,
                                                   iTermMultiServerServerOriginatedMessage *out) {
    memset(out, 0, sizeof(*out));
    iTermClientServerProtocolMessage temp = *message;
    // This pointer can dangle if the struct gets copied, so ensure it's a legit internal pointer.
    temp.message.msg_iov = message->ioVectors;
    iTermClientServerProtocolMessageParser parser = {
        .offset = 0,
        .message = &temp
    };

    if (iTermClientServerProtocolParseTaggedInt(&parser, &out->type, sizeof(out->type), iTermMultiServerTagType)) {
        return iTermMultiServerProtocolErrorMissingType;
    }
    switch (out->type) {
        case iTermMultiServerRPCTypeHandshake:
            return ParseHandshakeResponse(&parser, &out->payload.handshake);

        case iTermMultiServerRPCTypeLaunch: { // Server-originated response to client-originated request
            int rc = ParseLaunchResponse(&parser, &out->payload.launch);
            if (rc) {
                return rc;
            }
            return iTermMultiServerProtocolGetFileDescriptor(message, &out->payload.launch.fd);
        }
        case iTermMultiServerRPCTypeReportChild: {  // Server-originated, no response.
            int rc = ParseReportChild(&parser, &out->payload.reportChild);
            if (rc) {
                return rc;
            }
            return iTermMultiServerProtocolGetFileDescriptor(message, &out->payload.reportChild.fd);
        }
        case iTermMultiServerRPCTypeWait:
            return ParseWaitResponse(&parser, &out->payload.wait);

        case iTermMultiServerRPCTypeTermination: // Server-originated, no response.
            return ParseTermination(&parser, &out->payload.termination);

        case iTermMultiServerRPCTypeHello:  // Server-originated, no response.
            return ParseHello(&parser, &out->payload.hello);
    }
    return iTermMultiServerProtocolErrorUnknownType;
}

int iTermMultiServerProtocolEncodeMessageFromClient(iTermMultiServerClientOriginatedMessage *obj,
                                                    iTermClientServerProtocolMessage *message) {
    iTermClientServerProtocolMessageEncoder encoder = {
        .offset = 0,
        .message = message
    };

    int status = iTermClientServerProtocolEncodeTaggedInt(&encoder, &obj->type, sizeof(obj->type), iTermMultiServerTagType);
    if (status) {
        return status;
    }
    switch (obj->type) {
        case iTermMultiServerRPCTypeHandshake:
            status = EncodeHandshakeRequest(&encoder, &obj->payload.handshake);
            break;

        case iTermMultiServerRPCTypeLaunch:
            status = EncodeLaunchRequest(&encoder, &obj->payload.launch);
            break;

        case iTermMultiServerRPCTypeWait:
            status = EncodeWaitRequest(&encoder, &obj->payload.wait);
            break;

        case iTermMultiServerRPCTypeReportChild:
        case iTermMultiServerRPCTypeTermination:
        case iTermMultiServerRPCTypeHello:
            break;
    }
    if (!status) {
        iTermEncoderCommit(&encoder);
    }
    return status;
}

int iTermMultiServerProtocolEncodeMessageFromServer(iTermMultiServerServerOriginatedMessage *obj,
                                                    iTermClientServerProtocolMessage *message) {
    iTermClientServerProtocolMessageEncoder encoder = {
        .offset = 0,
        .message = message
    };
    int status = iTermClientServerProtocolEncodeTaggedInt(&encoder, &obj->type, sizeof(obj->type), iTermMultiServerTagType);
    if (status) {
        return status;
    }
    switch (obj->type) {
        case iTermMultiServerRPCTypeHandshake:
            status = EncodeHandshakeResponse(&encoder, &obj->payload.handshake);
            break;
        case iTermMultiServerRPCTypeLaunch:
            status = EncodeLaunchResponse(&encoder, &obj->payload.launch);
            break;
        case iTermMultiServerRPCTypeWait:
            status = EncodeWaitResponse(&encoder, &obj->payload.wait);
            break;
        case iTermMultiServerRPCTypeReportChild:
            status = EncodeReportChild(&encoder, &obj->payload.reportChild);
            break;
        case iTermMultiServerRPCTypeTermination:
            status = EncodeTermination(&encoder, &obj->payload.termination);
            break;
        case iTermMultiServerRPCTypeHello:
            status = EncodeHello(&encoder, &obj->payload.hello);
            break;
    }
    if (status) {
        FDLog(LOG_ERR, "Failed to encode message from server:");
    } else {
        iTermEncoderCommit(&encoder);
        FDLog(LOG_DEBUG, "Encoded:");
    }
    iTermMultiServerProtocolLogMessageFromServer(obj);
    return status;
}

static void FreeLaunchRequest(iTermMultiServerRequestLaunch *obj) {
    free((void *)obj->path);
    for (int i = 0; i < obj->argc; i++) {
        free((void *)obj->argv[i]);
    }
    free((void *)obj->argv);
    for (int i = 0; i < obj->envc; i++) {
        free((void *)obj->envp[i]);
    }
    free((void *)obj->envp);
    free((void *)obj->pwd);
    memset(obj, 0xab, sizeof(*obj));
}

static void FreeReportChild(iTermMultiServerReportChild *obj) {
    free((void *)obj->path);
    for (int i = 0; i < obj->argc; i++) {
        free((void *)obj->argv[i]);
    }
    free((void *)obj->argv);
    for (int i = 0; i < obj->envc; i++) {
        free((void *)obj->envp[i]);
    }
    free((void *)obj->envp);
    free((void *)obj->tty);
    memset(obj, 0xab, sizeof(*obj));
}

static void FreeHello(iTermMultiServerHello *obj) {
}

static void FreeWaitRequest(iTermMultiServerRequestWait *wait) {
}

static void FreeWaitResponse(iTermMultiServerResponseWait *wait) {
}

static void FreeHandshakeRequest(iTermMultiServerRequestHandshake *handshake) {
}

static void FreeHandshakeResponse(iTermMultiServerResponseHandshake *handshake) {
}

static void FreeLaunchResponse(iTermMultiServerResponseLaunch *launch) {
    free((void *)launch->tty);
}

void iTermMultiServerClientOriginatedMessageFree(iTermMultiServerClientOriginatedMessage *obj) {
    switch (obj->type) {
        case iTermMultiServerRPCTypeHandshake:
            FreeHandshakeRequest(&obj->payload.handshake);
            break;
        case iTermMultiServerRPCTypeLaunch:
            FreeLaunchRequest(&obj->payload.launch);
            break;
        case iTermMultiServerRPCTypeWait:
            FreeWaitRequest(&obj->payload.wait);
            break;
        case iTermMultiServerRPCTypeReportChild:
        case iTermMultiServerRPCTypeTermination:
        case iTermMultiServerRPCTypeHello:
            break;
    }
    memset(obj, 0xAB, sizeof(*obj));
}

void iTermMultiServerServerOriginatedMessageFree(iTermMultiServerServerOriginatedMessage *obj) {
    switch (obj->type) {
        case iTermMultiServerRPCTypeHandshake:
            FreeHandshakeResponse(&obj->payload.handshake);
            break;
        case iTermMultiServerRPCTypeLaunch:
            FreeLaunchResponse(&obj->payload.launch);
            break;
        case iTermMultiServerRPCTypeWait:
            FreeWaitResponse(&obj->payload.wait);
            break;
        case iTermMultiServerRPCTypeReportChild:
            FreeReportChild(&obj->payload.reportChild);
            break;
        case iTermMultiServerRPCTypeHello:
            FreeHello(&obj->payload.hello);
            break;
        case iTermMultiServerRPCTypeTermination:
            break;
    }
    memset(obj, 0xCD, sizeof(*obj));
}

static ssize_t RecvMsg(int fd,
                       iTermClientServerProtocolMessage *message) {
    assert(message->valid == ITERM_MULTISERVER_MAGIC);

    ssize_t n = -1;
    do {
        n = recvmsg(fd, &message->message, 0);
    } while (n < 0 && errno == EINTR);

    return n;
}

static ssize_t Read(int fd,
                    char *buffer,
                    size_t length) {
    assert(length > 0);
    ssize_t n = -1;
    ssize_t offset = 0;
    while (offset < length) {
        do {
            n = read(fd, buffer + offset, length - offset);
        } while (n < 0 && errno == EINTR);
        if (n <= 0) {
            FDLog(LOG_DEBUG, "read returned %d: %s", n, errno ? strerror(errno) : "EOF");
            return n;
        }
        offset += n;
        FDLog(LOG_DEBUG, "read returned %d. Have read %d/%d", n, (int)offset, (int)length);
    }

    return offset;
}

// Returns number of bytes read. 0 is not EOF.
ssize_t iTermMultiServerReadMessage(int fd, iTermClientServerProtocolMessage *message, ssize_t bufferSize) {
    assert(bufferSize >= 0);
    iTermClientServerProtocolMessageInitialize(message);
    iTermClientServerProtocolMessageEnsureSpace(message, bufferSize);
    const ssize_t recvStatus = RecvMsg(fd, message);
    if (recvStatus < 0) {
        iTermClientServerProtocolMessageFree(message);
    }

    return recvStatus;
}

int iTermMultiServerRead(int fd, iTermClientServerProtocolMessage *message) {
    iTermClientServerProtocolMessageInitialize(message);

    size_t length = 0;
    int status = 1;
    FDLog(LOG_DEBUG, "Want to read header (%d bytes)", (int)sizeof(length));
    ssize_t actuallyRead = Read(fd, (char *)&length, sizeof(length));
    if (actuallyRead < sizeof(length)) {
        FDLog(LOG_DEBUG, "While reading length: short read %d/%d", (int)actuallyRead, (int)length);
        goto done;
    }

    static const size_t MAX_MESSAGE_SIZE = 1024 * 1024;
    if (length <= 0 || length > MAX_MESSAGE_SIZE) {
        FDLog(LOG_DEBUG, "While reading length: Negative or oversize read of %d (%s)", (int)length, strerror(errno));
        goto done;
    }
    iTermClientServerProtocolMessageEnsureSpace(message, length);

    FDLog(LOG_DEBUG, "Want to read payload (%d bytes)", (int)length);
    actuallyRead = Read(fd, message->ioVectors[0].iov_base, length);
    if (actuallyRead < length) {
        FDLog(LOG_DEBUG, "While reading payload: actuallyRead=%d (%s)", (int)actuallyRead, strerror(errno));
        goto done;
    }
    FDLog(LOG_DEBUG, "Finished reading rc=%d %s", (int)actuallyRead, strerror(errno));

    status = 0;

done:
    if (status) {
        iTermClientServerProtocolMessageFree(message);
    }

    return status;
}

static void LogHandshakeRequest(iTermMultiServerRequestHandshake *message,
                                iTermMultiServerProtocolLogFunction logFunction) {
    LogToLogFunc("Handshake request [maximumProtocolVersion=%d]",
          message->maximumProtocolVersion);
}

static void LogLaunchRequest(iTermMultiServerRequestLaunch *message,
                             iTermMultiServerProtocolLogFunction logFunction) {
    LogToLogFunc("Launch request [path=%s columns=%d rows=%d pixel_width=%d pixel_height=%d isUTF8=%d pwd=%s uniqueId=%lld argc=%d envc=%d]",
          message->path,
          message->columns,
          message->rows,
          message->pixel_width,
          message->pixel_height,
          message->isUTF8,
          message->pwd,
          message->uniqueId,
          message->argc,
          message->envc);
    for (int i = 0; i < message->argc; i++) {
        LogToLogFunc("  Arg %d for launch request %lld: %s",
              i, message->uniqueId, message->argv[i]);
    }
    for (int i = 0; i < message->envc; i++) {
        LogToLogFunc("  Env %d for launch request %lld: %s",
              i, message->uniqueId, message->envp[i]);
    }
}

static void LogWaitRequest(iTermMultiServerRequestWait *message,
                           iTermMultiServerProtocolLogFunction logFunction) {
    LogToLogFunc("Wait Request [pid=%d removePreemptively=%d]",
          message->pid, message->removePreemptively);
}

void
iTermMultiServerProtocolLogMessageFromClient2(iTermMultiServerClientOriginatedMessage *message,
                                              iTermMultiServerProtocolLogFunction logFunction) {
    switch (message->type) {
        case iTermMultiServerRPCTypeHandshake:
            LogHandshakeRequest(&message->payload.handshake, logFunction);
            break;

        case iTermMultiServerRPCTypeLaunch:
            LogLaunchRequest(&message->payload.launch, logFunction);
            break;

        case iTermMultiServerRPCTypeReportChild:
            // Server-originated, no response.
            break;

        case iTermMultiServerRPCTypeWait:
            LogWaitRequest(&message->payload.wait, logFunction);
            break;

        case iTermMultiServerRPCTypeTermination:
        case iTermMultiServerRPCTypeHello:
            // Server-originated, no response.
            break;
    }
}

static void FDLogWrapper(const char *file, int line, const char *func, const char *format, ...) {
    va_list args;
    va_start(args, format);
    char *temp = NULL;
#if ITERM_SERVER
    extern const char *gMultiServerSocketPath;
    asprintf(&temp, "iTermServer(pid=%d, path=%s) %s:%d %s: %s", getpid(), gMultiServerSocketPath, file, line, func, format);
    vsyslog(LOG_DEBUG, temp, args);
#else
    // Because xcode is hot garbage, syslog(LOG_DEBUG) goes to its console so we turn that off for debug builds.
#if !DEBUG
    extern void DLogC(const char *format, va_list args);
    asprintf(&temp, "iTermClient(pid=%d) %s:%d %s: %s", getpid(), file, line, func, format);
    DLogC(temp, args);
#endif  // DEBUG
#endif  // ITERM_SERVER
    va_end(args);
    free(temp);
}

void
iTermMultiServerProtocolLogMessageFromClient(iTermMultiServerClientOriginatedMessage *message) {
    iTermMultiServerProtocolLogMessageFromClient2(message, FDLogWrapper);
}

static void LogHandshakeResponse(iTermMultiServerResponseHandshake *message,
                                 iTermMultiServerProtocolLogFunction logFunction) {
    LogToLogFunc("Handshake response [protocolVersion=%d numChildren=%d pid=%d]",
          message->protocolVersion,
          message->numChildren,
          message->pid);
}

static void LogLaunchResponse(iTermMultiServerResponseLaunch *message,
                              iTermMultiServerProtocolLogFunction logFunction) {
    LogToLogFunc("Launch response [status=%d pid=%d fd=%d uniqueId=%lld tty=%s]",
          message->status,
          message->pid,
          message->fd,
          message->uniqueId,
          message->tty);
}

static void LogReportChild(iTermMultiServerReportChild *message,
                           iTermMultiServerProtocolLogFunction logFunction) {
    LogToLogFunc("Report child [isLast=%d pid=%d path=%s isUTF8=%d pwd=%s terminated=%d tty=%s fd=%d argc=%d envc=%d]",
          message->isLast,
          message->pid,
          message->path,
          message->isUTF8,
          message->pwd,
          message->terminated,
          message->tty,
          message->fd,
          message->argc,
          message->envc);
    for (int i = 0; i < message->argc; i++) {
        LogToLogFunc("  Arg %d of child with pid %d: %s",
              i, message->pid, message->argv[i]);
    }
    for (int i = 0; i < message->envc; i++) {
        LogToLogFunc("  Env %d of child with pid %d: %s",
              i, message->pid, message->envp[i]);
    }
}

static void LogWaitResponse(iTermMultiServerResponseWait *message,
                            iTermMultiServerProtocolLogFunction logFunction) {
    LogToLogFunc("Wait response [pid=%d status=%d resultType=%d]",
          message->pid, message->status, message->resultType);
}

static void LogTermination(iTermMultiServerReportTermination *message,
                           iTermMultiServerProtocolLogFunction logFunction) {
    LogToLogFunc("Report termination [pid=%d]",
          message->pid);
}

static void LogHello(iTermMultiServerHello *message,
                     iTermMultiServerProtocolLogFunction logFunction) {
    LogToLogFunc("Hello");
}

void
iTermMultiServerProtocolLogMessageFromServer2(iTermMultiServerServerOriginatedMessage *message,
                                              iTermMultiServerProtocolLogFunction logFunction) {
    switch (message->type) {
        case iTermMultiServerRPCTypeHandshake:
            LogHandshakeResponse(&message->payload.handshake, logFunction);
            break;

        case iTermMultiServerRPCTypeLaunch:
            LogLaunchResponse(&message->payload.launch, logFunction);
            break;

        case iTermMultiServerRPCTypeReportChild:
            LogReportChild(&message->payload.reportChild, logFunction);
            break;

        case iTermMultiServerRPCTypeWait:
            LogWaitResponse(&message->payload.wait, logFunction);
            break;

        case iTermMultiServerRPCTypeTermination:
            LogTermination(&message->payload.termination, logFunction);
            break;

        case iTermMultiServerRPCTypeHello:
            LogHello(&message->payload.hello, logFunction);
            break;
    }
}

void
iTermMultiServerProtocolLogMessageFromServer(iTermMultiServerServerOriginatedMessage *message) {
    iTermMultiServerProtocolLogMessageFromServer2(message, FDLogWrapper);
}

