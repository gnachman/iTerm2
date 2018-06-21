//
//  UKCrashReporter.h
//  NiftyFeatures
//
//  Created by Uli Kusterer on Sat Feb 04 2006.
//  Copyright (c) 2006 M. Uli Kusterer. All rights reserved.
//

// -----------------------------------------------------------------------------
//	Headers:
// -----------------------------------------------------------------------------

#import <Foundation/Foundation.h>
#import "UKNibOwner.h"


// -----------------------------------------------------------------------------
//	Prototypes:
// -----------------------------------------------------------------------------

/* Call this sometime during startup (e.g. in applicationDidLaunch) and it'll
	check for a new crash log and offer to the user to send it.
	
	The crash log is sent to a CGI script whose URL you specify in the
	UKUpdateChecker.strings file. If you want, you can even have different
	URLs for different locales that way, in case a crash is caused by an error
	in a localized file.
*/
void	UKCrashReporterCheckForCrash(void);


// -----------------------------------------------------------------------------
//	Classes:
// -----------------------------------------------------------------------------

@interface UKCrashReporter : UKNibOwner
{
	IBOutlet NSWindow*				reportWindow;
	IBOutlet NSTextView*			informationField;
	IBOutlet NSTextView*			crashLogField;
	IBOutlet NSTextField*			explanationField;
	IBOutlet NSProgressIndicator*	progressIndicator;
	IBOutlet NSButton*				sendButton;
	IBOutlet NSButton*				remindButton;
	IBOutlet NSButton*				discardButton;
	IBOutlet NSTabView*				switchTabView;
	NSURLConnection*				connection;
	BOOL							feedbackMode;
}

-(id)		initWithLogString: (NSString*)theLog;
-(id)		init;									// This gives you a feedback window instead of a crash reporter.

-(IBAction)	sendCrashReport: (id)sender;
-(IBAction)	remindMeLater: (id)sender;
-(IBAction)	discardCrashReport: (id)sender;

@end


@interface UKFeedbackProvider : NSObject
{
	
}

-(IBAction) orderFrontFeedbackWindow: (id)sender;
-(IBAction) orderFrontBugReportWindow: (id)sender;

@end
