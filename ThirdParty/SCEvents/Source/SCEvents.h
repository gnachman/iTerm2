/*
 *  $Id: SCEvents.h 205 2011-06-18 15:16:08Z stuart $
 *
 *  SCEvents
 *  http://stuconnolly.com/projects/code/
 *
 *  Copyright (c) 2011 Stuart Connolly. All rights reserved.
 *
 *  Permission is hereby granted, free of charge, to any person
 *  obtaining a copy of this software and associated documentation
 *  files (the "Software"), to deal in the Software without
 *  restriction, including without limitation the rights to use,
 *  copy, modify, merge, publish, distribute, sublicense, and/or sell
 *  copies of the Software, and to permit persons to whom the
 *  Software is furnished to do so, subject to the following
 *  conditions:
 *
 *  The above copyright notice and this permission notice shall be
 *  included in all copies or substantial portions of the Software.
 * 
 *  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
 *  EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
 *  OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
 *  NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
 *  HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
 *  WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
 *  FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
 *  OTHER DEALINGS IN THE SOFTWARE.
 */

#import <Foundation/Foundation.h>
#import <CoreServices/CoreServices.h>

#import "SCEventListenerProtocol.h"

@class SCEvent;

/**
 * @class SCEvents SCEvents.h
 *
 * @author Stuart Connolly http://stuconnolly.com/
 *
 * An Objective-C wrapper for the FSEvents C API.
 */
@interface SCEvents : NSObject 
{
    id <NSObject, SCEventListenerProtocol> _delegate; 
    
    BOOL                 _isWatchingPaths;
    BOOL                 _ignoreEventsFromSubDirs;
	CFRunLoopRef         _runLoop;
    FSEventStreamRef     _eventStream;
    CFTimeInterval       _notificationLatency;
	FSEventStreamEventId _resumeFromEventId;
      
    SCEvent              *_lastEvent;
    NSArray              *_watchedPaths;
    NSArray              *_excludedPaths;
	
	pthread_mutex_t       _eventsLock;
}

/**
 * @property _delegate The delegate that SCEvents is to notify when events occur
 */
@property (readwrite, assign, getter=delegate, setter=setDelegate:) id <NSObject, SCEventListenerProtocol> _delegate;

/**
 * @property _isWatchingPaths Indicates whether the events stream is currently running
 */
@property (readonly, getter=isWatchingPaths) BOOL _isWatchingPaths;

/**
 * @property _ignoreEventsFromSubDirs Indicates whether events from sub-directories of the excluded paths are ignored. Defaults to YES.
 */
@property (readwrite, assign, getter=ignoreEventsFromSubDirs, setter=setIgnoreEventsFromSubDirs:) BOOL _ignoreEventsFromSubDirs;

/**
 * @property _lastEvent The last event that occurred and that was delivered to the delegate.
 */
@property (readwrite, retain, getter=lastEvent, setter=setLastEvent:) SCEvent *_lastEvent;

/**
 * @property _notificationLatency The latency time of which SCEvents is notified by FSEvents of events. Defaults to 3 seconds.
 */
@property (readwrite, assign, getter=notificationLatency, setter=setNotificationLatency:) double _notificationLatency;

/**
 * @property _watchedPaths The paths that are to be watched for events.
 */
@property (readwrite, retain, getter=watchedPaths, setter=setWatchedPaths:) NSArray *_watchedPaths;

/**
 * @property _excludedPaths The paths that SCEvents should ignore events from and not deliver to the delegate.
 */
@property (readwrite, retain, getter=excludedPaths, setter=setExcludedPaths:) NSArray *_excludedPaths;

/**
 * @property _resumeFromEventId The event ID from which to resume from when the stream is started.
 */
@property (readwrite, assign, getter=resumeFromEventId, setter=setResumeFromEventId:) FSEventStreamEventId _resumeFromEventId;

- (BOOL)flushEventStreamSync;
- (BOOL)flushEventStreamAsync;

- (BOOL)startWatchingPaths:(NSArray *)paths;
- (BOOL)startWatchingPaths:(NSArray *)paths onRunLoop:(NSRunLoop *)runLoop;

- (BOOL)stopWatchingPaths;

- (NSString *)streamDescription;

@end
