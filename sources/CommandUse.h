//
//  CommandUse.h
//  iTerm
//
//  Created by George Nachman on 1/19/14.
//
//

#import <Foundation/Foundation.h>

// When a session wants references to its marks released it should post this notification with
// the session GUID as the object.
extern NSString *const kCommandUseReleaseMarksInSession;

@class VT100ScreenMark;

@interface CommandUse : NSObject <NSCopying>

@property(nonatomic, assign) NSTimeInterval time;
@property(nonatomic, retain) VT100ScreenMark *mark;
@property(nonatomic, retain) NSString *directory;

// This is used to figure out which mark matches this command use when deserializing marks.
@property(nonatomic, copy) NSString *markGuid;

+ (instancetype)commandUseFromSerializedValue:(NSArray *)serializedValue;
- (NSArray *)serializedValue;

@end
