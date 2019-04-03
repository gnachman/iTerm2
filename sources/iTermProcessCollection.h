//
//  iTermProcessCollection.h
//  iTerm2
//
//  Created by George Nachman on 4/30/17.
//
//

#import <Foundation/Foundation.h>

@interface iTermProcessInfo : NSObject

@property(nonatomic, readonly, strong) NSString *name;
@property(nonatomic, readonly) pid_t processID;
@property(nonatomic, readonly) pid_t parentProcessID;
@property(nonatomic, readonly) NSMutableArray<iTermProcessInfo *> *children;
@property(nonatomic, weak, readonly) iTermProcessInfo *parent;
@property(nonatomic, readonly) BOOL isForegroundJob;
@property(nonatomic, readonly) NSArray<iTermProcessInfo *> *sortedChildren;

@property(nonatomic, weak, readonly) iTermProcessInfo *deepestForegroundJob;
@property(nonatomic, readonly) NSArray<iTermProcessInfo *> *flattenedTree;

- (void)resolveAsynchronously;

// This is to be used by tests
- (void)privateSetIsForegroundJob;

- (NSArray<iTermProcessInfo *> *)descendantsSkippingLevels:(NSInteger)levels;

@end

@interface iTermProcessCollection : NSObject

@property (nonatomic, readonly) NSString *treeString;

- (iTermProcessInfo *)addProcessWithProcessID:(pid_t)processID
                              parentProcessID:(pid_t)parentProcessID;

- (void)commit;

- (iTermProcessInfo *)infoForProcessID:(pid_t)processID;

@end

