//
//  iTermStatusBarRPCProvidedTextComponent.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 7/10/18.
//

#import "iTermStatusBarTextComponent.h"
#import "iTermStatusBarGraphicComponent.h"

@class ITMRPCRegistrationRequest;

@interface iTermStatusBarRPCProvidedTextComponent : iTermStatusBarTextComponent

- (instancetype)initWithRegistrationRequest:(ITMRPCRegistrationRequest *)registrationRequest
                                      scope:(iTermVariableScope *)scope
                                      knobs:(NSDictionary *)knobs;

@end

@interface iTermStatusBarRPCProvidedLineGraphComponent : iTermStatusBarSparklinesComponent

- (instancetype)initWithRegistrationRequest:(ITMRPCRegistrationRequest *)registrationRequest
                                      scope:(iTermVariableScope *)scope
                                      knobs:(NSDictionary *)knobs;

@end

@interface iTermStatusBarRPCComponentFactory : NSObject<iTermStatusBarComponentFactory>

- (instancetype)initWithRegistrationRequest:(ITMRPCRegistrationRequest *)registrationRequest;

@end

