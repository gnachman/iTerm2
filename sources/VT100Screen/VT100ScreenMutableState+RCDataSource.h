//
//  VT100ScreenMutableState+RCDataSource.h
//  iTerm2SharedARC
//
//  Isolates iTermSavedTreeRCDataSource's iTermResilientCoordinateDataSource
//  conformance into a category so VT100ScreenMutableState.h (which is in
//  the Swift bridging header) doesn't have to import the Swift bridging
//  header to see the protocol's full definition. That would create a cycle:
//  the bridging header includes VT100ScreenMutableState.h to generate
//  iTerm2SharedARC-Swift.h.
//
//  This header imports the Swift bridging header to see the protocol's full
//  definition. Anyone who needs the conformance (e.g. to read .rcGuid off an
//  iTermSavedTreeRCDataSource, or to pass one where an
//  id<iTermResilientCoordinateDataSource> is expected) imports this category.
//  The main bridging header does NOT include this file.
//

#import "VT100ScreenMutableState.h"
#import "iTerm2SharedARC-Swift.h"

NS_ASSUME_NONNULL_BEGIN

@interface iTermSavedTreeRCDataSource (RCDataSource) <iTermResilientCoordinateDataSource>
@end

NS_ASSUME_NONNULL_END
