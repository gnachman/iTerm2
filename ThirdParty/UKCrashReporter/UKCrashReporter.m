//
//  UKCrashReporter.m
//  NiftyFeatures
//
//  Created by Uli Kusterer on Sat Feb 04 2006.
//  Copyright (c) 2006 M. Uli Kusterer. All rights reserved.
//

// -----------------------------------------------------------------------------
//    Headers:
// -----------------------------------------------------------------------------

#import "UKCrashReporter.h"
#import "UKSystemInfo.h"

@interface UKCrashReporterWindow: NSWindow
@end

@implementation UKCrashReporterWindow

- (void)closeCurrentSession:(id)sender {
    [self performClose:sender];
}

@end

NSString*    UKCrashReporterFindTenFiveCrashReportPath( NSString* appName, NSArray *folders );

static NSString *UKReadErrorLog(void) {
    NSString *executableName =
        [[[NSBundle mainBundle] infoDictionary] objectForKey:(id)kCFBundleExecutableKey];
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory,
                                                         NSUserDomainMask,
                                                         YES);
    NSString *path = paths.firstObject;
    if (!path) {
        return nil;
    }
    if (executableName) {
        path = [path stringByAppendingPathComponent:executableName];
    }

    NSMutableString *result = [NSMutableString string];
    for (NSInteger i = 0; i < 3; i++) {
        path = [path stringByAppendingPathComponent:[NSString stringWithFormat:@"log.%ld.txt", i]];
        if (!path) {
            break;
        }
        NSString *log = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
        if (log) {
            [result appendString:log];
        }
        [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
    }
    return result;
}

// -----------------------------------------------------------------------------
//    UKCrashReporterCheckForCrash:
//        This submits the crash report to a CGI form as a POST request by
//        passing it as the request variable "crashlog".
//    
//        KNOWN LIMITATION:    If the app crashes several times in a row, only the
//                            last crash report will be sent because this doesn't
//                            walk through the log files to try and determine the
//                            dates of all reports.
//
//        This is written so it works back to OS X 10.2, or at least gracefully
//        fails by just doing nothing on such older OSs. This also should never
//        throw exceptions or anything on failure. This is an additional service
//        for the developer and *mustn't* interfere with regular operation of the
//        application.
// -----------------------------------------------------------------------------

void    UKCrashReporterCheckForCrash(void)
{
    NSAutoreleasePool*    pool = [[NSAutoreleasePool alloc] init];

    NS_DURING
        // Try whether the classes we need to talk to the CGI are present:
        Class            NSMutableURLRequestClass = NSClassFromString( @"NSMutableURLRequest" );
        Class            NSURLConnectionClass = NSClassFromString( @"NSURLConnection" );
        if( NSMutableURLRequestClass == Nil || NSURLConnectionClass == Nil )
        {
            [pool release];
            NS_VOIDRETURN;
        }
        
        // Get the log file, its last change date and last report date:
        NSString*        appName = [[[NSBundle mainBundle] infoDictionary] objectForKey: @"CFBundleExecutable"];
        NSArray *folders = @[ [@"~/Library/Logs/DiagnosticReports/" stringByExpandingTildeInPath],
                              [@"~/Library/Logs/CrashReporter/" stringByExpandingTildeInPath] ];
        NSString*        crashLogPath = UKCrashReporterFindTenFiveCrashReportPath( appName, folders );
        NSDictionary*    fileAttrs = [[NSFileManager defaultManager] 
                                     attributesOfItemAtPath: crashLogPath error: nil];
        NSDate*            lastTimeCrashLogged = (fileAttrs == nil) ? nil : [fileAttrs fileModificationDate];
        NSTimeInterval    lastCrashReportInterval = [[NSUserDefaults standardUserDefaults] floatForKey: @"UKCrashReporterLastCrashReportDate"];
        NSDate*            lastTimeCrashReported = [NSDate dateWithTimeIntervalSince1970: lastCrashReportInterval];

        NSString *errorLog = nil;
        @try {
            errorLog = UKReadErrorLog();
        } @catch (NSException *exception) {
            errorLog = [exception debugDescription];
        }

        if( lastTimeCrashLogged )    // We have a crash log file and its mod date? Means we crashed sometime in the past.
        {
            // If we never before reported a crash or the last report lies before the last crash:
            if( [lastTimeCrashReported compare: lastTimeCrashLogged] == NSOrderedAscending )
            {
                // Fetch the newest report from the log:
                NSString*            crashLog = [NSString stringWithContentsOfFile:crashLogPath
                                                                 encoding:NSUTF8StringEncoding
                                                                    error:nil];
                NSString *const ERROR_LOG_HEADER = @"~~ Error Logs ~~\n";
                if (![crashLog containsString:ERROR_LOG_HEADER]) {
                    crashLog = [crashLog stringByAppendingString:ERROR_LOG_HEADER];
                    if (errorLog != nil) {
                        crashLog = [crashLog stringByAppendingString:errorLog];
                    }
                    [crashLog writeToFile:crashLogPath atomically:NO encoding:NSUTF8StringEncoding error:nil];
                }
                NSArray*            separateReports = [crashLog componentsSeparatedByString: @"\n\n**********\n\n"];
                NSString*            currentReport = [separateReports count] > 0 ? [separateReports objectAtIndex: [separateReports count] -1] : @"*** Couldn't read Report ***";    // 1 since report 0 is empty (file has a delimiter at the top).
                unsigned            numCores = UKCountCores();
                NSString*            numCPUsString = (numCores == 1) ? @"" : [NSString stringWithFormat: @"%dx ",numCores];
                
                // Create a string containing Mac and CPU info, crash log and prefs:
                currentReport = [NSString stringWithFormat:
                                    @"Model: %@\nCPU Speed: %@%.2f GHz\n%@\n",
                                    UKMachineName(), numCPUsString, ((float)UKClockSpeed()) / 1000.0f,
                                    currentReport];
                
                // Now show a crash reporter window so the user can edit the info to send:
                [[UKCrashReporter alloc] initWithLogString: currentReport];
            }
        }
    NS_HANDLER
        NSLog(@"Error during check for crash: %@",localException);
    NS_ENDHANDLER
    
    [pool release];
}

NSString* UKCrashReporterFindTenFiveCrashReportPath(NSString* appName, NSArray *folders)
{
    NSString* currName = nil;
    NSString* crashLogPrefix = [NSString stringWithFormat:@"%@_",appName];
    NSString* crashLogSuffix = @".crash";
    NSString* foundName = nil;
    NSDate* foundDate = nil;
    NSString* foundFolder = nil;
    
    for (NSString *crashLogsFolder in folders) {
        // Find the newest of our crash log files:
        NSDirectoryEnumerator*    enny =
            [[NSFileManager defaultManager] enumeratorAtPath:crashLogsFolder];
        while ((currName = [enny nextObject])) {
            if ([currName hasPrefix:crashLogPrefix] && [currName hasSuffix:crashLogSuffix] ) {
                NSDate*    currDate = [[enny fileAttributes] fileModificationDate];
                if (foundName) {
                    if ([currDate isGreaterThan:foundDate]) {
                        foundName = currName;
                        foundDate = currDate;
                        foundFolder = crashLogsFolder;
                    }
                } else {
                    foundName = currName;
                    foundDate = currDate;
                    foundFolder = crashLogsFolder;
                }
            }
        }
    }

    if( !foundName )
        return nil;
    else
        return [foundFolder stringByAppendingPathComponent:foundName];
}


NSString*    gCrashLogString = nil;


@implementation UKCrashReporter {
    NSURLSessionDataTask *_dataTask;
}

-(id)    initWithLogString: (NSString*)theLog
{
    // In super init the awakeFromNib method gets called, so we can not
    //    use ivars to transfer the log, and use a global instead:
    gCrashLogString = [theLog retain];
    
    self = [super init];
    return self;
}


-(id)    init
{
    self = [super init];
    if( self )
    {
        feedbackMode = YES;
    }
    return self;
}


-(void) dealloc
{
    [_dataTask release];
    _dataTask = nil;
    
    [super dealloc];
}

- (BOOL)europeanLocale {
    NSString *cc = [[NSLocale currentLocale] countryCode];
    NSArray *europeanCountryCodes = @[ @"BE", @"BG", @"CZ", @"DK", @"DE", @"EE", @"IE", @"EL", @"ES", @"FR",
                                       @"HR", @"IT", @"CY", @"LV", @"LT", @"LU", @"HU", @"MT", @"NL", @"AT",
                                       @"PL", @"PT", @"RO", @"SI", @"SK", @"FI", @"SE", @"UK" ];
    return !cc || [europeanCountryCodes containsObject:cc];
}

-(void)    awakeFromNib
{
    // Insert the app name into the explanation message:
    NSString*            appName = [[NSFileManager defaultManager] displayNameAtPath: [[NSBundle mainBundle] bundlePath]];
    NSMutableString*    explanation = nil;
    if( gCrashLogString )
        explanation = [[[explanationField stringValue] mutableCopy] autorelease];
    else
        explanation = [[NSLocalizedStringFromTable(@"FEEDBACK_EXPLANATION_TEXT",@"UKCrashReporter",@"") mutableCopy] autorelease];
    [explanation replaceOccurrencesOfString: @"%%APPNAME" withString: appName
                                    options: 0 range: NSMakeRange(0, [explanation length])];
    [explanationField setStringValue: explanation];
    
    // Insert user name and e-mail address into the information field:
    NSMutableString*    userMessage = nil;
    if( gCrashLogString )
        userMessage = [[[informationField string] mutableCopy] autorelease];
    else
        userMessage = [[NSLocalizedStringFromTable(@"FEEDBACK_MESSAGE_TEXT",@"UKCrashReporter",@"") mutableCopy] autorelease];

    NSString *emailAddr = NSLocalizedStringFromTable(@"MISSING_EMAIL_ADDRESS",@"UKCrashReporter",@"");

    if ([self europeanLocale]) {
        emailAddr = NSLocalizedStringFromTable(@"MISSING_EMAIL_ADDRESS",@"UKCrashReporter",@"");
    }

    [userMessage replaceOccurrencesOfString: @"%%LONGUSERNAME" withString: NSFullUserName()
                options: 0 range: NSMakeRange(0, [userMessage length])];
    [userMessage replaceOccurrencesOfString: @"%%EMAILADDRESS" withString: emailAddr
                options: 0 range: NSMakeRange(0, [userMessage length])];
    [informationField setString: userMessage];
    
    // Show the crash log to the user:
    if( gCrashLogString )
    {
        [crashLogField setString: gCrashLogString];
        [gCrashLogString release];
        gCrashLogString = nil;
    }
    else
    {
        [remindButton setHidden: YES];
        
        int                itemIndex = [switchTabView indexOfTabViewItemWithIdentifier: @"de.zathras.ukcrashreporter.crashlog-tab"];
        NSTabViewItem*    crashLogItem = [switchTabView tabViewItemAtIndex: itemIndex];
        unsigned        numCores = UKCountCores();
        NSString*        numCPUsString = (numCores == 1) ? @"" : [NSString stringWithFormat: @"%dx ",numCores];
        [crashLogItem setLabel: NSLocalizedStringFromTable(@"SYSTEM_INFO_TAB_NAME",@"UKCrashReporter",@"")];
        
        NSString*    systemInfo = [NSString stringWithFormat: @"Application: %@ %@\nModel: %@\nCPU Speed: %@%.2f GHz\nSystem Version: %@\n\nPreferences:\n%@",
                                    appName, [[[NSBundle mainBundle] infoDictionary] objectForKey: @"CFBundleVersion"],
                                    UKMachineName(), numCPUsString, ((float)UKClockSpeed()) / 1000.0f,
                                    UKSystemVersionString(),
                                    [[NSUserDefaults standardUserDefaults] persistentDomainForName: [[NSBundle mainBundle] bundleIdentifier]]];
        [crashLogField setString: systemInfo];
    }
    
    // Show the window:
    [reportWindow makeKeyAndOrderFront: self];
}


-(IBAction)    sendCrashReport: (id)sender
{
    NSString            *boundary = @"0xKhTmLbOuNdArY";
    NSMutableString*    crashReportString = [NSMutableString string];
    [crashReportString appendString: [informationField string]];
    [crashReportString appendString: @"\n==========\n"];
    [crashReportString appendString: [crashLogField string]];
    [crashReportString replaceOccurrencesOfString: boundary withString: @"USED_TO_BE_KHTMLBOUNDARY" options: 0 range: NSMakeRange(0, [crashReportString length])];
    NSData*                crashReport = [crashReportString dataUsingEncoding: NSUTF8StringEncoding];
    
    // Prepare a request:
    NSURL *url = [NSURL URLWithString: NSLocalizedStringFromTable( @"CRASH_REPORT_CGI_URL", @"UKCrashReporter", @"" )];
    NSMutableURLRequest *postRequest = [NSMutableURLRequest requestWithURL: url];
    NSString            *contentType = [NSString stringWithFormat:@"multipart/form-data; boundary=%@",boundary];
    NSString            *agent = @"UKCrashReporter";

    // Add form trappings to crashReport:
    NSData*            header = [[NSString stringWithFormat:@"--%@\r\nContent-Disposition: form-data; name=\"crashlog\"\r\n\r\n", boundary] dataUsingEncoding:NSUTF8StringEncoding];
    NSMutableData*    formData = [[header mutableCopy] autorelease];
    [formData appendData: crashReport];
    [formData appendData:[[NSString stringWithFormat:@"\r\n--%@--\r\n",boundary] dataUsingEncoding:NSUTF8StringEncoding]];
    
    // setting the headers:
    [postRequest setHTTPMethod: @"POST"];
    [postRequest setValue: url.host forHTTPHeaderField: @"Host"];
    [postRequest setValue: contentType forHTTPHeaderField: @"Content-Type"];
    [postRequest setValue: agent forHTTPHeaderField: @"User-Agent"];
    NSString *contentLength = [NSString stringWithFormat:@"%lu", (unsigned long)[formData length]];
    [postRequest setValue: contentLength forHTTPHeaderField: @"Content-Length"];
    [postRequest setHTTPBody: formData];
    
    // Go into progress mode and kick off the HTTP post:
    [progressIndicator startAnimation: self];
    [sendButton setEnabled: NO];
    [remindButton setEnabled: NO];
    [discardButton setEnabled: NO];

    _dataTask = [[NSURLSession sharedSession] dataTaskWithRequest:postRequest completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
        if (error) {
            [self performSelectorOnMainThread: @selector(showFinishedMessage:) withObject: error waitUntilDone: NO];
            return;
        }
        // Now that we successfully sent this crash, don't report it again:
        if (!feedbackMode) {
            [[NSUserDefaults standardUserDefaults] setFloat: [[NSDate date] timeIntervalSince1970] forKey:@"UKCrashReporterLastCrashReportDate"];
            [[NSUserDefaults standardUserDefaults] synchronize];
        }

        [self performSelectorOnMainThread: @selector(showFinishedMessage:) withObject: nil waitUntilDone: NO];
    }];
    [_dataTask retain];
    [_dataTask resume];
}


-(IBAction)    remindMeLater: (id)sender
{
    [reportWindow orderOut: self];
}


-(IBAction)    discardCrashReport: (id)sender
{
    // Remember we already did this crash, so we don't ask twice:
    if( !feedbackMode )
    {
        [[NSUserDefaults standardUserDefaults] setFloat: [[NSDate date] timeIntervalSince1970] forKey: @"UKCrashReporterLastCrashReportDate"];
        [[NSUserDefaults standardUserDefaults] synchronize];
    }

    [reportWindow orderOut: self];
}


-(void)    showFinishedMessage: (NSError*)errMsg
{
    if( errMsg )
    {
        NSString*        errTitle = nil;
        if( feedbackMode )
            errTitle = NSLocalizedStringFromTable( @"COULDNT_SEND_FEEDBACK_ERROR",@"UKCrashReporter",@"");
        else
            errTitle = NSLocalizedStringFromTable( @"COULDNT_SEND_CRASH_REPORT_ERROR",@"UKCrashReporter",@"");

        NSAlert *alert = [[[NSAlert alloc] init] autorelease];
        alert.messageText = errTitle;
        alert.informativeText = [errMsg localizedDescription];
        [alert addButtonWithTitle:NSLocalizedStringFromTable( @"COULDNT_SEND_CRASH_REPORT_ERROR_OK",@"UKCrashReporter",@"")];
        [alert runModal];
    }
    
    [reportWindow orderOut: self];
    [self autorelease];
}


@end


@implementation UKFeedbackProvider

-(IBAction) orderFrontFeedbackWindow: (id)sender
{
    [[UKCrashReporter alloc] init];
}


-(IBAction) orderFrontBugReportWindow: (id)sender
{
    [[UKCrashReporter alloc] init];
}

@end
