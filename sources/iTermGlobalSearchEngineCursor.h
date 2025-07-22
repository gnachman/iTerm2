//
//  iTermGlobalSearchEngineCursor.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 8/22/20.
//

#import <Foundation/Foundation.h>
#import "iTermFindViewController.h"
#import "iTermGlobalSearchResult.h"

@class FindContext;
@class PTYSession;
@class iTermSearchEngine;

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSUInteger, iTermGlobalSearchEngineCursorPass) {
    iTermGlobalSearchEngineCursorPassMainScreen,
    iTermGlobalSearchEngineCursorPassCurrentScreen
};

@protocol iTermGlobalSearchEngineCursorProtocol<NSObject>
- (void)drainFully:(void (^ NS_NOESCAPE)(NSArray<iTermGlobalSearchResult *> *, NSUInteger))handler;
- (BOOL)consumeAvailable:(void (^ NS_NOESCAPE)(NSArray<iTermGlobalSearchResult *> *, NSUInteger))handler;
- (PTYSession *)session;
- (id<iTermGlobalSearchEngineCursorProtocol> _Nullable)instanceForNextPass;
- (long long)approximateLinesSearched;
@end

@interface iTermGlobalSearchEngineCursor: NSObject<iTermGlobalSearchEngineCursorProtocol>
@property (nonatomic, strong) PTYSession *session;
@property (nonatomic, strong) iTermSearchEngine *searchEngine;
@property (nonatomic) iTermGlobalSearchEngineCursorPass pass;
@property (nonatomic, copy) NSString *query;
@property (nonatomic) iTermFindMode mode;
@property (nonatomic) BOOL currentScreenIsAlternate;
@property (nonatomic, readonly) long long expectedLines;
@property (nonatomic, copy) void (^willPause)(iTermGlobalSearchEngineCursor *);

- (instancetype)initWithQuery:(NSString *)query
                         mode:(iTermFindMode)mode
                      session:(PTYSession *)session;
- (instancetype)init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
