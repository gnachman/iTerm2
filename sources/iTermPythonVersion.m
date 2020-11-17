//
//  iTermPythonVersion.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 11/17/20.
//

#import "iTermPythonVersion.h"

NSString *const iTermPythonProtocolVersionString = @"1.8";

const int iTermMinimumPythonEnvironmentVersion = 70;

// SEE ALSO iTermMinimumPythonEnvironmentVersion
// NOTE: Modules older than 0.69 did not report too-old errors correctly.
//
// *WARNING*****************************************************************************************
// *WARNING* Think carefully before changing this. It will break existing full-environment scripts.*
// *WARNING*****************************************************************************************
//
NSString *const iTermWebSocketConnectionMinimumPythonLibraryVersion = @"0.24";
