//
//  iTermLoggingHelper.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 12/4/19.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class iTermLoggingHelper;
@class iTermVariableScope;

@protocol iTermLogging<NSObject>
- (void)loggingHelperStart:(iTermLoggingHelper *)loggingHelper;
- (void)loggingHelperStop:(iTermLoggingHelper *)loggingHelper;
@end

extern NSString *const iTermLoggingHelperErrorNotificationName;
extern NSString *const iTermLoggingHelperErrorNotificationGUIDKey;

@interface iTermLoggingHelper : NSObject

@property (nullable, nonatomic, readonly) NSString *path;
@property (nonatomic, readonly) BOOL enabled;
@property (nonatomic, readonly) BOOL plainText;
@property (nullable, nonatomic, weak) id<iTermLogging> rawLogger;
@property (nullable, nonatomic, weak) id<iTermLogging> plainLogger;
@property (nonatomic, readonly) BOOL appending;
@property (nonatomic, readonly) iTermVariableScope *scope;

+ (void)observeNotificationsWithHandler:(void (^)(NSString *guid))handler;

- (instancetype)initWithRawLogger:(id<iTermLogging>)rawLogger
                      plainLogger:(id<iTermLogging>)plainLogger
                      profileGUID:(NSString *)profileGUID
                            scope:(iTermVariableScope *)scope NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;

- (void)setPath:(NSString *)path enabled:(BOOL)enabled plainText:(BOOL)plainText append:(nullable NSNumber *)append;
- (void)stop;

- (void)logData:(NSData *)data;
- (void)logNewline;

@end

NS_ASSUME_NONNULL_END
