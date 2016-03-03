//
//  iTermNativeViewFactory.m
//  iTerm2
//
//  Created by George Nachman on 3/1/16.
//
//

#import "iTermNativeViewFactory.h"
#import "DebugLogging.h"
#import "FutureMethods.h"
#import "NSData+iTerm.h"
#import "iTermNativeInteractiveViewController.h"
#import "iTermNativeWebViewController.h"

static NSString *const kPresentationKey = @"presentation";
static NSString *const kAppKey = @"app";
static NSString *const kArgumentsKey = @"arguments";

/*
 {
   "app": "WebView",
   "arguments": {
     "url": "https://google.com/"
   }
 }
 */

@implementation iTermNativeViewFactory

+ (iTermNativeViewController *)nativeViewControllerWithDescriptor:(NSString *)descriptor {
    NSData *data = [NSData dataWithBase64EncodedString:descriptor];
    if (!data) {
        return nil;
    }

    NSError *error = nil;
    id root = [NSJSONSerialization JSONObjectWithData:data
                                              options:0
                                                error:&error];
    if (!root || error) {
        DLog(@"Failed to parse json %@: %@", descriptor, error);
        return nil;
    }

    if (![root isKindOfClass:[NSDictionary class]]) {
        DLog(@"Bogus json: %@", root);
        return nil;
    }

    NSDictionary *presentation = root[kPresentationKey];
    if (presentation && ![presentation isKindOfClass:[NSDictionary class]]) {
        DLog(@"Presentation not a dictionary: %@", presentation);
        return nil;
    }

    NSString *app = root[kAppKey];
    if (![app isKindOfClass:[NSString class]]) {
        DLog(@"Bogus app: %@", app);
        return nil;
    }

    NSDictionary *arguments = root[kArgumentsKey];
    if (arguments && ![arguments isKindOfClass:[NSDictionary class]]) {
        DLog(@"Bogus arguments: %@", arguments);
        return nil;
    }

    NSString *factoryMethod = [self factoryMethodForAppNamed:app];
    if (!factoryMethod) {
        DLog(@"Unregistered app name: %@", app);
        return nil;
    }

    SEL selector = NSSelectorFromString(factoryMethod);
    assert([self respondsToSelector:selector]);

    return [self performSelector:selector withObject:arguments];
}

+ (iTermNativeViewController *)webViewFactory:(NSDictionary *)arguments {
    return [[iTermNativeWebViewController alloc] initWithDictionary:arguments];
}

+ (iTermNativeViewController *)interactiveViewFactory:(NSDictionary *)arguments {
    return [[iTermNativeInteractiveViewController alloc] initWithDictionary:arguments];
}

+ (NSString *)factoryMethodForAppNamed:(NSString *)name {
    NSDictionary *factoryMethods = @{ @"WebView": NSStringFromSelector(@selector(webViewFactory:)),
                                      @"Interactive": NSStringFromSelector(@selector(interactiveViewFactory:)) };
    return factoryMethods[name];
}

@end
