//
//  iTermWeakReference.h
//  iTerm2
//
//  Created by George Nachman on 2/6/16.
//
//

#import <Foundation/Foundation.h>

@interface iTermWeakReference<ObjectType> : NSObject

// When object is dealloc'ed this pointer becomes nil. No attempts at thread safety here; only
// suitable for objects that get dealloced on the main thread.
@property(nonatomic, readonly) ObjectType object;

+ (instancetype)weakReferenceToObject:(ObjectType)object;

@end
