//
//  iTermPromotionalMessageManager.h
//  iTerm
//
//  Created by George Nachman on 5/7/15.
//
//

#import <Cocoa/Cocoa.h>

@interface iTermPromotionalMessageManager : NSObject {
    NSMutableData *_data;
    NSString *_downloadFilename;
    NSURLResponse *_response;
    NSURLDownload *_download;
    NSArray *_promotion;  // An array of [ promoId, message, title, url ]
    BOOL _scheduled;
}

+ (instancetype)sharedInstance;
- (void)scheduleDisplayIfNeeded;

@end
