//
//  iTermPythonVersion.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 11/17/20.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// This is sent to the Python runtime when it connects. It describes the capabilities of iTerm2 for
// the runtime to decide which features are available.
extern NSString *const iTermPythonProtocolVersionString;

// SEE ALSO iTermWebSocketConnectionMinimumPythonLibraryVersion
// NOTE: This does not affect full-environment scripts.
// Increasing this makes everyone download a new version.
extern const int iTermMinimumPythonEnvironmentVersion;

// SEE ALSO iTermMinimumPythonEnvironmentVersion
// NOTE: Modules older than 0.69 did not report too-old errors correctly.
//
// *WARNING*****************************************************************************************
// *WARNING* Think carefully before changing this. It will break existing full-environment scripts.*
// *WARNING*****************************************************************************************
//
extern NSString *const iTermWebSocketConnectionMinimumPythonLibraryVersion;

NS_ASSUME_NONNULL_END
