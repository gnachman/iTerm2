//
//  VT100ScreenState+RCDataSource.h
//  iTerm2SharedARC
//
//  Isolates iTermResilientCoordinateDataSource conformance into a
//  category so VT100ScreenState.h doesn't have to redeclare the
//  protocol's required methods (forward declaration alone wouldn't
//  expose them) and doesn't have to import the Swift bridging header
//  (which would create a cycle: the bridging header includes
//  VT100ScreenState.h to generate iTerm2SharedARC-Swift.h).
//
//  This header imports the Swift bridging header to see the protocol's
//  full definition. Anyone who needs the conformance — currently just
//  VT100ScreenMutableState.m, which overrides -rcGuid — imports this
//  category. The main bridging header does NOT include this file.
//

#import "VT100ScreenState.h"
#import "iTerm2SharedARC-Swift.h"

NS_ASSUME_NONNULL_BEGIN

@interface VT100ScreenState (RCDataSource) <iTermResilientCoordinateDataSource>
@end

NS_ASSUME_NONNULL_END
