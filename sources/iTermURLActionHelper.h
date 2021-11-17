//
//  iTermURLActionHelper.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/16/19.
//

#import <Cocoa/Cocoa.h>

#import "ProfileModel.h"
#import "VT100GridTypes.h"

NS_ASSUME_NONNULL_BEGIN

@class iTermImageInfo;
@protocol iTermObject;
@class iTermSelection;
@class iTermSemanticHistoryController;
@class iTermTextExtractor;
@class iTermURLActionHelper;
@class iTermVariableScope;
@class Profile;
@class SCPPath;
@class SmartMatch;
@class URLAction;
@class VT100RemoteHost;

@protocol iTermURLActionHelperDelegate<NSObject>
- (BOOL)urlActionHelperShouldIgnoreHardNewlines:(iTermURLActionHelper *)helper;
- (iTermImageInfo *)urlActionHelper:(iTermURLActionHelper *)helper imageInfoAt:(VT100GridCoord)coord;
- (iTermTextExtractor *)urlActionHelperNewTextExtractor:(iTermURLActionHelper *)helper;
- (void)urlActionHelper:(iTermURLActionHelper *)helper workingDirectoryOnLine:(int)line completion:(void (^)(NSString *workingDirectory))completion;

- (SCPPath *)urlActionHelper:(iTermURLActionHelper *)helper
       secureCopyPathForFile:(NSString *)path onLine:(int)line;

- (VT100GridCoord)urlActionHelper:(iTermURLActionHelper *)helper
                    coordForEvent:(NSEvent *)event
         allowRightMarginOverflow:(BOOL)allowRightMarginOverflow;

- (VT100GridAbsCoord)urlActionHelper:(iTermURLActionHelper *)helper
                    absCoordForEvent:(NSEvent *)event
            allowRightMarginOverflow:(BOOL)allowRightMarginOverflow;

- (long long)urlActionTotalScrollbackOverflow:(iTermURLActionHelper *)helper;

- (VT100RemoteHost *)urlActionHelper:(iTermURLActionHelper *)helper remoteHostOnLine:(int)line;

- (NSDictionary<NSNumber *, NSString *> *)urlActionHelperSmartSelectionActionSelectorDictionary:(iTermURLActionHelper *)helper;
- (NSArray<NSDictionary<NSString *, id> *> *)urlActionHelperSmartSelectionRules:(iTermURLActionHelper *)helper;
- (void)urlActionHelper:(iTermURLActionHelper *)helper startSecureCopyDownload:(SCPPath *)path;
- (NSDictionary *)urlActionHelperAttributes:(iTermURLActionHelper *)helper;
- (NSPoint)urlActionHelper:(iTermURLActionHelper *)helper pointForCoord:(VT100GridCoord)coord;
- (NSScreen *)urlActionHelperScreen:(iTermURLActionHelper *)helper;
- (CGFloat)urlActionHelperLineHeight:(iTermURLActionHelper *)helper;
- (void)urlActionHelper:(iTermURLActionHelper *)helper launchProfileInCurrentTerminal:(Profile *)profile withURL:(NSURL *)url;
- (iTermVariableScope *)urlActionHelperScope:(iTermURLActionHelper *)helper;
- (id<iTermObject>)urlActionHelperOwner:(iTermURLActionHelper *)helper;
- (void)urlActionHelperCopySelectionIfNeeded:(iTermURLActionHelper *)helper;
- (iTermSelection *)urlActionHelperSelection:(iTermURLActionHelper *)helper;
@end

@interface iTermURLActionHelper : NSObject
@property (nonatomic, weak) id<iTermURLActionHelperDelegate> delegate;
@property (nonatomic, strong, readonly) iTermSemanticHistoryController *semanticHistoryController;
@property (nonatomic, weak) id smartSelectionActionTarget;

- (instancetype)initWithSemanticHistoryController:(iTermSemanticHistoryController *)semanticHistoryController NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

- (BOOL)ignoreHardNewlinesInURLs;

- (void)urlActionForClickAtCoord:(VT100GridCoord)coord
                      completion:(void (^)(URLAction * _Nullable))completion;

- (void)urlActionForClickAtCoord:(VT100GridCoord)coord
          respectingHardNewlines:(BOOL)respectHardNewlines
                      completion:(void (^)(URLAction * _Nullable))completion;

- (void)openTargetWithEvent:(NSEvent *)event inBackground:(BOOL)openInBackground;

- (void)findUrlInString:(NSString *)aURLString andOpenInBackground:(BOOL)background;

- (void)downloadFileAtSecureCopyPath:(SCPPath *)scpPath
                         displayName:(NSString *)name
                      locationInView:(VT100GridCoordRange)range;

- (SmartMatch *)smartSelectAtAbsoluteCoord:(VT100GridAbsCoord)coord
                                        to:(VT100GridAbsWindowedRange *)rangePtr
                          ignoringNewlines:(BOOL)ignoringNewlines
                            actionRequired:(BOOL)actionRequired
                           respectDividers:(BOOL)respectDividers;

- (void)smartSelectWithEvent:(NSEvent *)event;

- (void)smartSelectAndMaybeCopyWithEvent:(NSEvent *)event
                        ignoringNewlines:(BOOL)ignoringNewlines;

- (void)openSemanticHistoryPath:(NSString *)path
                  orRawFilename:(NSString *)rawFileName
                       fragment:(NSString * _Nullable)fragment
               workingDirectory:(NSString *)workingDirectory
                     lineNumber:(NSString *)lineNumber
                   columnNumber:(NSString *)columnNumber
                         prefix:(NSString *)prefix
                         suffix:(NSString *)suffix
                     completion:(void (^)(BOOL ok))completion;

@end

NS_ASSUME_NONNULL_END
