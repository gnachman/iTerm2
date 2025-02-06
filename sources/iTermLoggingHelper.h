//
//  iTermLoggingHelper.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 12/4/19.
//

#import <Foundation/Foundation.h>
#import "ITAddressBookMgr.h"
#import "VT100GridTypes.h"

NS_ASSUME_NONNULL_BEGIN

@class iTermLoggingHelper;
@class iTermVariableScope;

@protocol iTermLogging<NSObject>
- (void)loggingHelperStart:(iTermLoggingHelper *)loggingHelper;
- (void)loggingHelperStop:(iTermLoggingHelper *)loggingHelper;

@optional
// Cooked logger must implement this
- (NSString * _Nullable)loggingHelperTimestamp:(iTermLoggingHelper *)loggingHelper;
@end

extern NSString *const iTermLoggingHelperErrorNotificationName;
extern NSString *const iTermLoggingHelperErrorNotificationGUIDKey;

@interface iTermAsciicastMetadata: NSObject
@property (nonatomic, readonly) int width;
@property (nonatomic, readonly) int height;
@property (nonatomic, readonly, copy) NSString *command;
@property (nonatomic, readonly, copy) NSString *title;
@property (nonatomic, readonly, copy) NSDictionary *environment;
@property (nonatomic, readonly, readonly) NSTimeInterval startTime;  // since boot
@property (nonatomic, readonly) NSString *fgString;
@property (nonatomic, readonly) NSString *bgString;
@property (nonatomic, readonly) NSString *paletteString;

- (instancetype)initWithWidth:(int)width
                       height:(int)height
                      command:(NSString *)command
                        title:(NSString *)title
                  environment:(NSDictionary *)environment
                           fg:(NSColor *)fg
                           bg:(NSColor *)bg
                         ansi:(NSArray<NSColor *> *)ansi NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;
@end

@interface iTermLoggingHelper : NSObject

@property (nullable, nonatomic, readonly) NSString *path;
@property (nonatomic, readonly) BOOL enabled;
@property (nonatomic, readonly) iTermLoggingStyle style;
@property (nullable, nonatomic, weak) id<iTermLogging> rawLogger;
@property (nullable, nonatomic, weak) id<iTermLogging> cookedLogger;
@property (nonatomic, readonly) BOOL appending;
@property (nonatomic, readonly) iTermVariableScope *scope;
@property (nonatomic, strong) iTermAsciicastMetadata *asciicastMetadata;

+ (void)observeNotificationsWithHandler:(void (^)(NSString *guid))handler;

- (instancetype)initWithRawLogger:(id<iTermLogging>)rawLogger
                     cookedLogger:(id<iTermLogging>)cookedLogger
                      profileGUID:(NSString *)profileGUID
                            scope:(iTermVariableScope *)scope NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;

- (void)setPath:(NSString *)path enabled:(BOOL)enabled
          style:(iTermLoggingStyle)style
asciicastMetadata:(iTermAsciicastMetadata *)asciicastMetadata
         append:(nullable NSNumber *)append
         window:(nullable NSWindow *)window;
- (void)stop;

- (void)logData:(NSData *)data;
- (void)logNewline:(NSData * _Nullable)data;
- (void)logWithoutTimestamp:(NSData *)data;
- (void)logSetSize:(VT100GridSize)size;

@end

NS_ASSUME_NONNULL_END
