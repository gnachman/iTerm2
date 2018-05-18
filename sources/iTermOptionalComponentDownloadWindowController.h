//
//  iTermOptionalComponentDownloadWindowController.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/27/18.
//

#import <Cocoa/Cocoa.h>

extern const int iTermMinimumPythonEnvironmentVersion;

@class iTermOptionalComponentDownloadWindowController;

@protocol iTermOptionalComponentDownloadWindowControllerDelegate<NSObject>
- (void)optionalComponentDownload:(iTermOptionalComponentDownloadWindowController *)sender didFinishWithError:(NSError *)error;
@end

@interface iTermOptionalComponentDownloadPhase : NSObject
@property (nonatomic, copy, readonly) NSURL *url;
@property (nonatomic, strong, readonly) NSInputStream *stream;
@property (nonatomic, strong, readonly) NSError *error;
@property (nonatomic, copy, readonly) iTermOptionalComponentDownloadPhase *(^nextPhaseFactory)(iTermOptionalComponentDownloadPhase *);
@property (nonatomic, copy, readonly) NSString *title;

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithURL:(NSURL *)url
                      title:(NSString *)title          
           nextPhaseFactory:(iTermOptionalComponentDownloadPhase *(^)(iTermOptionalComponentDownloadPhase *))nextPhaseFactory;

@end

@interface iTermManifestDownloadPhase : iTermOptionalComponentDownloadPhase
@property (nonatomic, readonly) NSURL *nextURL;
@property (nonatomic, readonly) NSString *signature;
@property (nonatomic, readonly) int version;

- (instancetype)initWithURL:(NSURL *)url
           nextPhaseFactory:(iTermOptionalComponentDownloadPhase *(^)(iTermOptionalComponentDownloadPhase *))nextPhaseFactory;
@end

@interface iTermPayloadDownloadPhase : iTermOptionalComponentDownloadPhase
@property (nonatomic, copy, readonly) NSString *expectedSignature;

- (instancetype)initWithURL:(NSURL *)url expectedSignature:(NSString *)expectedSignature NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithURL:(NSURL *)url
                      title:(NSString *)title
           nextPhaseFactory:(iTermOptionalComponentDownloadPhase *(^)(iTermOptionalComponentDownloadPhase *))nextPhaseFactory NS_UNAVAILABLE;

@end

@interface iTermOptionalComponentDownloadWindowController : NSWindowController
@property (nonatomic, copy) void (^completion)(iTermOptionalComponentDownloadPhase *);
@property (nonatomic, readonly) iTermOptionalComponentDownloadPhase *currentPhase;

- (void)beginPhase:(iTermOptionalComponentDownloadPhase *)phase;
- (void)showMessage:(NSString *)message;

@end

