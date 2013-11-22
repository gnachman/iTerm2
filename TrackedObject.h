//
//  TrackedObject.h
//  iTerm
//
//  Created by George Nachman on 11/21/13.
//
//

#import <Foundation/Foundation.h>

@protocol TrackedObject <NSObject>

@property(nonatomic, assign) BOOL isInLineBuffer;

// If in line buffer, this is the absolute position in the line buffer of the tracked object.
@property(nonatomic, assign) long long absolutePosition;

// If not line buffer, this is the absolute line number of the tracked object.
@property(nonatomic, assign) long long absoluteLineNumber;

@end
