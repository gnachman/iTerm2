// Implements the interface to the pty session.

#import <Foundation/Foundation.h>

#import "iTermFileDescriptorClient.h"
#import "iTermLoggingHelper.h"
#import "iTermTTYState.h"
#import "VT100GridTypes.h"

#import <termios.h>

@class Coprocess;
@class iTermProcessInfo;
@protocol iTermTask;
@class iTermWinSizeController;
@class PTYTab;
@class PTYTask;

@protocol PTYTaskDelegate <NSObject>
// Runs in a background thread. Should do as much work as possible in this
// thread before kicking off a possibly async task in the main thread.
- (void)threadedReadTask:(char *)buffer length:(int)length;

// Runs in the same background task as -threadedReadTask:length:.
- (void)threadedTaskBrokenPipe;
- (void)brokenPipe;  // Called in main thread
- (void)tmuxClientWrite:(NSData *)data;

// Called on main thread from within launchWithPath:arguments:environment:customShell:gridSize:viewSize:isUTF8:.
- (void)taskDiedImmediately;

// Main thread
- (void)taskDidChangeTTY:(PTYTask *)task;
// Main thread
- (void)taskDidRegister:(PTYTask *)task;

- (void)taskDidChangePaused:(PTYTask *)task paused:(BOOL)paused;
- (void)taskMuteCoprocessDidChange:(PTYTask *)task hasMuteCoprocess:(BOOL)hasMuteCoprocess;
@end

typedef NS_ENUM(NSUInteger, iTermJobManagerForkAndExecStatus) {
    iTermJobManagerForkAndExecStatusSuccess,
    iTermJobManagerForkAndExecStatusTempFileError,
    iTermJobManagerForkAndExecStatusFailedToFork,
    iTermJobManagerForkAndExecStatusTaskDiedImmediately,
    iTermJobManagerForkAndExecStatusServerError,
    iTermJobManagerForkAndExecStatusServerLaunchFailed
};

typedef NS_ENUM(NSUInteger, iTermJobManagerKillingMode) {
    iTermJobManagerKillingModeRegular,            // SIGHUP, child only
    iTermJobManagerKillingModeForce,              // SIGKILL, child only
    iTermJobManagerKillingModeForceUnrestorable,  // SIGKILL to server if available. SIGHUP to child always.
    iTermJobManagerKillingModeProcessGroup,       // SIGHUP to process group
    iTermJobManagerKillingModeBrokenPipe,         // Removes unix domain socket and file descriptor for it. Ensures server is waitpid()ed on. This does not directly kill the child process.
};

typedef struct {
    pid_t pid;
    int number;
} iTermFileDescriptorMultiServerProcess;

typedef NS_ENUM(NSUInteger, iTermGeneralServerConnectionType) {
    iTermGeneralServerConnectionTypeMono,
    iTermGeneralServerConnectionTypeMulti
};

typedef struct {
    iTermGeneralServerConnectionType type;
    union {
        iTermFileDescriptorServerConnection mono;
        iTermFileDescriptorMultiServerProcess multi;
    };
} iTermGeneralServerConnection;

@protocol iTermJobManagerPartialResult<NSObject>
@end

@protocol iTermJobManager<NSObject>

@property (atomic) int fd;
@property (atomic, copy) NSString *tty;
@property (atomic, readonly) pid_t externallyVisiblePid;
@property (atomic, readonly) BOOL hasJob;
@property (atomic, readonly) id sessionRestorationIdentifier;
@property (atomic, readonly) pid_t pidToWaitOn;
@property (atomic, readonly) BOOL isSessionRestorationPossible;
@property (atomic, readonly) BOOL ioAllowed;
@property (atomic, readonly) dispatch_queue_t queue;
@property (atomic, readonly) BOOL isReadOnly;

+ (BOOL)available;

- (instancetype)initWithQueue:(dispatch_queue_t)queue;

- (void)forkAndExecWithTtyState:(iTermTTYState)ttyState
                        argpath:(NSString *)argpath
                           argv:(NSArray<NSString *> *)argv
                     initialPwd:(NSString *)initialPwd
                     newEnviron:(NSArray<NSString *> *)newEnviron
                           task:(id<iTermTask>)task
                     completion:(void (^)(iTermJobManagerForkAndExecStatus))completion;

typedef NS_OPTIONS(NSUInteger, iTermJobManagerAttachResults) {
    iTermJobManagerAttachResultsAttached = (1 << 0),
    iTermJobManagerAttachResultsRegistered = (1 << 1)
};

// Completion block will be invoked on the main thread. ok gives whether it succeeded.
- (void)attachToServer:(iTermGeneralServerConnection)serverConnection
         withProcessID:(NSNumber *)thePid
                  task:(id<iTermTask>)task
            completion:(void (^)(iTermJobManagerAttachResults results))completion;

- (iTermJobManagerAttachResults)attachToServer:(iTermGeneralServerConnection)serverConnection
                                 withProcessID:(NSNumber *)thePid
                                          task:(id<iTermTask>)task;

- (void)killWithMode:(iTermJobManagerKillingMode)mode;

// Atomic. Only closes it once. Returns YES if close() called, NO if already closed.
- (BOOL)closeFileDescriptor;

@optional
// Attach to the server before an iTermTask exists.
- (void)asyncPartialAttachToServer:(iTermGeneralServerConnection)serverConnection
                     withProcessID:(NSNumber *)thePid
                        completion:(void (^)(id<iTermJobManagerPartialResult> result))completion;

// After a partial attach, call this to register (if needed) and compute the attach results.
- (iTermJobManagerAttachResults)finishAttaching:(id<iTermJobManagerPartialResult>)result
                                           task:(id<iTermTask>)task;

@end

@protocol iTermPartialAttachment
@property (nonatomic, strong) id<iTermJobManagerPartialResult> partialResult;
@property (nonatomic, strong) id<iTermJobManager> jobManager;
@property (nonatomic, strong) dispatch_queue_t queue;
@end

@interface PTYTask : NSObject<iTermLogging>

@property(atomic, readonly) BOOL hasMuteCoprocess;
@property(atomic, weak) id<PTYTaskDelegate> delegate;

// No reading or writing allowed for now.
@property(atomic, assign) BOOL paused;
@property(nonatomic, readonly) BOOL isSessionRestorationPossible;
@property(nonatomic, readonly) id sessionRestorationIdentifier;

@property(atomic, readonly) int fd;
@property(atomic, readonly) pid_t pid;
// Externally, only PTYSession should assign to this when reattaching to a server.
@property(atomic, readonly) NSString *tty;
@property(atomic, readonly) NSString *path;
@property(atomic, readonly) NSString *getWorkingDirectory;
@property(atomic, readonly) BOOL hasOutput;
@property(atomic, readonly) BOOL wantsRead;
@property(atomic, readonly) BOOL wantsWrite;
@property(atomic, retain) Coprocess *coprocess;
@property(atomic, readonly) BOOL writeBufferHasRoom;
@property(atomic, readonly) BOOL hasCoprocess;
@property(nonatomic, readonly) BOOL passwordInput;
@property(nonatomic) unichar pendingHighSurrogate;
@property(nonatomic, copy) NSNumber *tmuxClientProcessID;
// This is used by tmux clients as a way to route data from %output in to the taskNotifier. Like
// the name says you can't write to it.
@property(atomic) int readOnlyFileDescriptor;

// This is used by clients so they can initialize the TTY size once when the view size is known
// for real. It is never assigned to by PTYTask.
@property(nonatomic) BOOL ttySizeInitialized;
@property (nonatomic, readonly) iTermWinSizeController *winSizeController;

- (instancetype)init;

- (BOOL)hasBrokenPipe;

// Command the profile was created with. nil for login shell or whatever's in the command field of the profile otherwise.
- (NSString *)originalCommand;

- (void)launchWithPath:(NSString*)progpath
             arguments:(NSArray*)args
           environment:(NSDictionary*)env
           customShell:(NSString *)customShell
              gridSize:(VT100GridSize)gridSize
              viewSize:(NSSize)viewSize
      maybeScaleFactor:(CGFloat)maybeScaleFactor
                isUTF8:(BOOL)isUTF8
            completion:(void (^)(void))completion;

- (void)writeTask:(NSData*)data;

- (void)stop;

// Called on any thread
- (void)brokenPipe;
- (void)processRead;
- (void)processWrite;

- (void)stopCoprocess;

// Monoserver:
// If [iTermAdvancedSettingsModel runJobsInServers] is on, then try for up to
// |timeout| seconds to connect to the server. Returns YES on success.
// If successful, it will be wired up as the task's file descriptor and process.
- (BOOL)tryToAttachToServerWithProcessId:(pid_t)thePid tty:(NSString *)tty;

// Multiserver
- (iTermJobManagerAttachResults)tryToAttachToMultiserverWithRestorationIdentifier:(NSDictionary *)restorationIdentifier;

// Wire up the server as the task's file descriptor and process. The caller
// will have connected to the server to get this info. Requires
// [iTermAdvancedSettingsModel runJobsInServers]. Multiservers may return failure (NO) here
// if the pid is not known.
- (void)attachToServer:(iTermGeneralServerConnection)serverConnection
            completion:(void (^)(iTermJobManagerAttachResults results))completion;

// Synchronous version of attachToServer:completion:
- (iTermJobManagerAttachResults)attachToServer:(iTermGeneralServerConnection)serverConnection;

- (void)killWithMode:(iTermJobManagerKillingMode)mode;

- (void)registerTmuxTask;

- (void)getWorkingDirectoryWithCompletion:(void (^)(NSString *pwd))completion;

- (void)partiallyAttachToMultiserverWithRestorationIdentifier:(NSDictionary *)restorationIdentifier
                                                   completion:(void (^)(id<iTermJobManagerPartialResult>))completion;

- (iTermJobManagerAttachResults)finishAttachingToMultiserver:(id<iTermJobManagerPartialResult>)partialResult
                                                  jobManager:(id<iTermJobManager>)jobManager
                                                       queue:(dispatch_queue_t)queue;

@end
