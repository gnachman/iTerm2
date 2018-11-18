#import "NMSSH.h"

typedef NS_OPTIONS(NSUInteger, NMSSHLogLevel) {
    NMSSHLogLevelVerbose = (1 << 0 | 1 << 1 | 1 << 2 | 1 << 3),
    NMSSHLogLevelInfo    = (1 << 1 | 1 << 2 | 1 << 3),
    NMSSHLogLevelWarn    = (1 << 2 | 1 << 3),
    NMSSHLogLevelError   = (1 << 3)
};

/**
 NMSSHLogger provides the functionality to customize the framework logging.
 */
@interface NMSSHLogger : NSObject

/// ----------------------------------------------------------------------------
/// @name Retrieve the shared logger
/// ----------------------------------------------------------------------------

/**
 Retrieve the shared logger instance
 
 @returns Shared logger
 */
+ (nonnull instancetype)logger NS_SWIFT_NAME(shared());

/// ----------------------------------------------------------------------------
/// @name Logger settings
/// ----------------------------------------------------------------------------

/**
 The block called to print the log message.

 The default implementation print the log
 message using NSLog.

 The block takes two argument:

 _level_ - Log level<br>
 _format_ - Log message
 */
@property (nonatomic, nonnull, copy) void (^logBlock)(NMSSHLogLevel level, NSString * _Nonnull format);

/** The maximum log level */
@property (nonatomic, assign) NMSSHLogLevel logLevel;

/** Enable or disable the logging feature */
@property (nonatomic, assign, getter = isEnabled) BOOL enabled;

/// ----------------------------------------------------------------------------
/// @name Logging
/// ----------------------------------------------------------------------------

/**
 Log with verbose level

 @param format Log message
 */
- (void)logVerbose:(nonnull NSString *)format;

/**
 Log with info level

 @param format Log message
 */
- (void)logInfo:(nonnull NSString *)format;

/**
 Log with warn level

 @param format Log message
 */
- (void)logWarn:(nonnull NSString *)format;

/**
 Log with error level

 @param format Log message
 */
- (void)logError:(nonnull NSString *)format;

@end
