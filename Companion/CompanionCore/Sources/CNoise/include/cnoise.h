//
//  cnoise.h
//  CNoise
//
//  Swift-facing umbrella header for the vendored noise-c library. It exposes
//  the full noise-c C API (<noise/protocol.h>) plus a handful of `static const
//  int` aliases for noise-c constants that Swift's Clang importer refuses to
//  import because they expand through the function-like NOISE_ID() macro (e.g.
//  NOISE_ROLE_INITIATOR == NOISE_ID('R', 1)). Swift cannot see those, so we
//  re-publish the ones the Swift layer needs as plain typed constants.
//

#ifndef CNOISE_H
#define CNOISE_H

#include <noise/protocol.h>

// Roles (handshake start). NOISE_ROLE_* expand through NOISE_ID(); alias them.
static const int CNoiseRoleInitiator = NOISE_ROLE_INITIATOR;
static const int CNoiseRoleResponder = NOISE_ROLE_RESPONDER;

// Handshake actions returned by noise_handshakestate_get_action().
static const int CNoiseActionNone = NOISE_ACTION_NONE;
static const int CNoiseActionWriteMessage = NOISE_ACTION_WRITE_MESSAGE;
static const int CNoiseActionReadMessage = NOISE_ACTION_READ_MESSAGE;
static const int CNoiseActionFailed = NOISE_ACTION_FAILED;
static const int CNoiseActionSplit = NOISE_ACTION_SPLIT;
static const int CNoiseActionComplete = NOISE_ACTION_COMPLETE;

// The subset of error codes the Swift layer checks by name.
static const int CNoiseErrorNone = NOISE_ERROR_NONE;

#endif /* CNOISE_H */
