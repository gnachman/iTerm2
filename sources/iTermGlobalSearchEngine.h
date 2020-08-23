//
//  iTermGlobalSearchEngine.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 8/22/20.
//

#import <Cocoa/Cocoa.h>

#import "iTermFindViewController.h"
#import "iTermGlobalSearchResult.h"

@class PTYSession;

NS_ASSUME_NONNULL_BEGIN

@interface iTermGlobalSearchEngine: NSObject
@property (nonatomic) iTermFindMode mode;
@property (nonatomic, readonly, copy) NSString *query;
@property (nonatomic, readonly, copy) void (^handler)(PTYSession * _Nullable, NSArray<iTermGlobalSearchResult *> * _Nullable, double);
@property (nonatomic, readonly, copy) NSArray<PTYSession *> *sessions;

- (instancetype)initWithQuery:(NSString *)query
                     sessions:(NSArray<PTYSession *> *)sessions
                         mode:(iTermFindMode)mode
                      handler:(void (^)(PTYSession * _Nullable session,
                                        NSArray<iTermGlobalSearchResult *> * _Nullableresults,
                                        double))handler NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

- (void)stop;

@end

NS_ASSUME_NONNULL_END
