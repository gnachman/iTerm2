//
//  iTermImage+SandboxedWorker.h
//  iTerm2SandboxedWorker
//
//  Created by Benedek Kozma on 2020. 12. 27..
//

#import <Foundation/Foundation.h>
#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

// Has to be the same class name as in the main app for NSSecureCoding.
@interface iTermImage : NSObject <NSSecureCoding>

@property(nonatomic) NSMutableArray<NSNumber *> *delays;
@property(nonatomic) NSSize size;
@property(nonatomic) NSMutableArray<NSImage *> *images;

- (instancetype)initWithData:(NSData *)data;

@end

NS_ASSUME_NONNULL_END
