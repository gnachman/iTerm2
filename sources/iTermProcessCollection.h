//
//  iTermProcessCollection.h
//  iTerm2
//
//  Created by George Nachman on 4/30/17.
//
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@protocol iTermProcessDataSource;
@class iTermProcessInfo;

@interface iTermProcessCollection : NSObject

@property (nonatomic, readonly) NSString *treeString;

- (instancetype)initWithDataSource:(id<iTermProcessDataSource>)dataSource NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

- (iTermProcessInfo *)addProcessWithProcessID:(pid_t)processID
                              parentProcessID:(pid_t)parentProcessID;

- (void)commit;

- (iTermProcessInfo * _Nullable)infoForProcessID:(pid_t)processID;

@end

NS_ASSUME_NONNULL_END
