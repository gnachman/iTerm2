//
//  iTermProcessCollection.h
//  iTerm2
//
//  Created by George Nachman on 4/30/17.
//
//

#import <Foundation/Foundation.h>

@interface iTermProcessInfo : NSObject

@property(nonatomic, retain) NSString *name;
@property(nonatomic, assign) pid_t processID;
@property(nonatomic, assign) pid_t parentProcessID;
@property(nonatomic, readonly) NSMutableArray<iTermProcessInfo *> *children;
@property(nonatomic, weak) iTermProcessInfo *parent;
@property(nonatomic, assign) BOOL isForegroundJob;

@property(nonatomic, weak, readonly) iTermProcessInfo *deepestForegroundJob;

@end

@interface iTermProcessCollection : NSObject

@property (nonatomic, readonly) NSString *treeString;

- (void)addProcessWithName:(NSString *)name
                 processID:(pid_t)processID
           parentProcessID:(pid_t)parentProcessID
           isForegroundJob:(BOOL)isForegroundJob;

- (void)commit;

- (iTermProcessInfo *)infoForProcessID:(pid_t)processID;

@end

