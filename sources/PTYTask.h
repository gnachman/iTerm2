// Implements the interface to the pty session.

#import <Foundation/Foundation.h>
#import "iTermFileDescriptorClient.h"

extern NSString *kCoprocessStatusChangeNotification;

@class Coprocess;
@class PTYTab;

@protocol PTYTaskDelegate <NSObject>
// Runs in a background thread. Should do as much work as possible in this
// thread before kicking off a possibly async task in the main thread.
- (void)threadedReadTask:(char *)buffer length:(int)length;

// Runs in the same background task as -threadedReadTask:length:.
- (void)threadedTaskBrokenPipe;
- (void)brokenPipe;  // Called in main thread
- (void)taskWasDeregistered;
- (void)writeForCoprocessOnlyTask:(NSData *)data;
@end

@interface PTYTask : NSObject

@property(atomic, readonly) BOOL hasMuteCoprocess;
@property(atomic, assign) id<PTYTaskDelegate> delegate;

// No reading or writing allowed for now.
@property(atomic, assign) BOOL paused;
@property(nonatomic, readonly) BOOL pidIsChild;
@property(nonatomic, readonly) pid_t serverPid;

// Tmux sessions are coprocess-only tasks. They have no file descriptor or pid,
// but they may have a coprocess that needs TaskNotifier to read, write, and wait on.
@property(atomic, assign) BOOL isCoprocessOnly;
@property(atomic, readonly) BOOL coprocessOnlyTaskIsDead;

- (id)init;
- (void)dealloc;
- (BOOL)hasBrokenPipe;
- (NSString *)command;
- (void)launchWithPath:(NSString*)progpath
             arguments:(NSArray*)args
           environment:(NSDictionary*)env
                 width:(int)width
                height:(int)height
                isUTF8:(BOOL)isUTF8;

- (NSString*)currentJob:(BOOL)forceRefresh;

- (void)writeTask:(NSData*)data;

- (void)sendSignal:(int)signo;
- (void)setWidth:(int)width height:(int)height;
- (void)stop;

- (int)fd;
- (pid_t)pid;
- (int)status;
- (NSString*)tty;
- (NSString*)path;
- (NSString*)getWorkingDirectory;
- (NSString*)description;

- (BOOL)startLoggingToFileWithPath:(NSString*)path shouldAppend:(BOOL)shouldAppend;
- (void)stopLogging;
- (BOOL)logging;
- (BOOL)hasOutput;

- (BOOL)wantsRead;
- (BOOL)wantsWrite;
- (void)brokenPipe;
- (void)processRead;
- (void)processWrite;

- (void)setCoprocess:(Coprocess *)coprocess;
- (Coprocess *)coprocess;
- (BOOL)writeBufferHasRoom;
- (BOOL)hasCoprocess;
- (void)stopCoprocess;

- (void)logData:(const char *)buffer length:(int)length;

// If [iTermAdvancedSettingsModel runJobsInServers] is on, then try for up to
// |timeout| seconds to connect to the server. Returns YES on success.
// If successful, it will be wired up as the task's file descriptor and process.
- (BOOL)tryToAttachToServerWithProcessId:(pid_t)thePid;

// Wire up the server as the task's file descriptor and process. The caller
// will ahve connected to the server to get this info. Requires
// [iTermAdvancedSettingsModel runJobsInServers].
- (void)attachToServer:(iTermFileDescriptorServerConnection)serverConnection;

// Clients should call this from tha main thread on a broken pipe.
- (void)killServerIfRunning;

- (void)registerAsCoprocessOnlyTask;
- (void)writeToCoprocessOnlyTask:(NSData *)data;

@end

