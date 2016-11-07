//
//  iTermAPIServer.h
//  iTerm2
//
//  Created by George Nachman on 11/3/16.
//
//

#import <Foundation/Foundation.h>
#import "Api.pbobjc.h"

@protocol iTermAPIServerDelegate<NSObject>
- (void)apiServerGetBuffer:(ITMGetBufferRequest *)request handler:(void (^)(ITMGetBufferResponse *))handler;
- (void)apiServerGetPrompt:(ITMGetPromptRequest *)request handler:(void (^)(ITMGetPromptResponse *))handler;
@end

@interface iTermAPIServer : NSObject

@property (nonatomic, weak) id<iTermAPIServerDelegate> delegate;

@end
