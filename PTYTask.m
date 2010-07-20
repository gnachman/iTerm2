// -*- mode:objc -*-
/*
 **  PTYTask.m
 **
 **  Copyright (c) 2002, 2003
 **
 **  Author: Fabian, Ujwal S. Setlur
 **	     Initial code by Kiichi Kusama
 **
 **  Project: iTerm
 **
 **  Description: Implements the interface to the pty session.
 **
 **  This program is free software; you can redistribute it and/or modify
 **  it under the terms of the GNU General Public License as published by
 **  the Free Software Foundation; either version 2 of the License, or
 **  (at your option) any later version.
 **
 **  This program is distributed in the hope that it will be useful,
 **  but WITHOUT ANY WARRANTY; without even the implied warranty of
 **  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 **  GNU General Public License for more details.
 **
 **  You should have received a copy of the GNU General Public License
 **  along with this program; if not, write to the Free Software
 **  Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
 */

// Debug option
#define DEBUG_ALLOC         0
#define DEBUG_METHOD_TRACE  0


#define MAXRW 2048

#import <Foundation/Foundation.h>

#include <unistd.h>
#include <util.h>
#include <sys/ioctl.h>
#include <sys/select.h>

#import <iTerm/PTYTask.h>
#import <iTerm/PreferencePanel.h>

#include <dlfcn.h>
#include <sys/mount.h>
/* Definition stolen from libproc.h */
#define PROC_PIDVNODEPATHINFO 9
//int proc_pidinfo(pid_t pid, int flavor, uint64_t arg,  void *buffer, int buffersize);

struct vinfo_stat {
	uint32_t	vst_dev;	/* [XSI] ID of device containing file */
	uint16_t	vst_mode;	/* [XSI] Mode of file (see below) */
	uint16_t	vst_nlink;	/* [XSI] Number of hard links */
	uint64_t	vst_ino;	/* [XSI] File serial number */
	uid_t		vst_uid;	/* [XSI] User ID of the file */
	gid_t		vst_gid;	/* [XSI] Group ID of the file */
	int64_t		vst_atime;	/* [XSI] Time of last access */
	int64_t		vst_atimensec;	/* nsec of last access */
	int64_t		vst_mtime;	/* [XSI] Last data modification time */
	int64_t		vst_mtimensec;	/* last data modification nsec */
	int64_t		vst_ctime;	/* [XSI] Time of last status change */
	int64_t		vst_ctimensec;	/* nsec of last status change */
	int64_t		vst_birthtime;	/*  File creation time(birth)  */
	int64_t		vst_birthtimensec;	/* nsec of File creation time */
	off_t		vst_size;	/* [XSI] file size, in bytes */
	int64_t		vst_blocks;	/* [XSI] blocks allocated for file */
	int32_t		vst_blksize;	/* [XSI] optimal blocksize for I/O */
	uint32_t	vst_flags;	/* user defined flags for file */
	uint32_t	vst_gen;	/* file generation number */
	uint32_t	vst_rdev;	/* [XSI] Device ID */
	int64_t		vst_qspare[2];	/* RESERVED: DO NOT USE! */
};

struct vnode_info {
	struct vinfo_stat	vi_stat;
	int			vi_type;
	fsid_t			vi_fsid;
	int			vi_pad;
};

struct vnode_info_path {
	struct vnode_info	vip_vi;
	char vip_path[MAXPATHLEN];  /* tail end of it  */
};

struct proc_vnodepathinfo {
	struct vnode_info_path pvi_cdir;
	struct vnode_info_path pvi_rdir;
};




@interface TaskNotifier : NSObject
{
	NSMutableArray* tasks;
	int unblockPipeR;
	int unblockPipeW;
}

+ (TaskNotifier*)sharedInstance;

- (id)init;
- (void)dealloc;

- (void)registerTask:(PTYTask*)task;
- (void)deregisterTask:(PTYTask*)task;

- (void)unblock;
- (void)run;

@end

@implementation TaskNotifier

static TaskNotifier* taskNotifier = nil;

+ (TaskNotifier*)sharedInstance
{
	if(!taskNotifier) {
		taskNotifier = [[TaskNotifier alloc] init];
		[NSThread detachNewThreadSelector:@selector(run)
				toTarget:taskNotifier withObject:nil];
	}
	return taskNotifier;
}

- (id)init
{
	if ([super init] == nil)
		return nil;

	tasks = [[NSMutableArray alloc] init];

	int unblockPipe[2];
	if(pipe(unblockPipe) != 0) {
		return nil;
	}
	fcntl(unblockPipe[0], F_SETFL, O_NONBLOCK);
	unblockPipeR = unblockPipe[0];
	unblockPipeW = unblockPipe[1];

	return self;
}

- (void)dealloc
{
	[tasks release];
	close(unblockPipeR);
	close(unblockPipeW);
	[super dealloc];
}

- (void)registerTask:(PTYTask*)task
{
	[tasks addObject:task];
	[self unblock];
}

- (void)deregisterTask:(PTYTask*)task
{
	[tasks removeObject:task];
	[self unblock];
}

- (void)unblock
{
	char dummy = 0;
	write(unblockPipeW, &dummy, 1);
}

- (void)run
{
	NSAutoreleasePool* outerPool = [[NSAutoreleasePool alloc] init];

	fd_set rfds;
	fd_set wfds;
	fd_set efds;
	int highfd;
	NSEnumerator* iter;
	PTYTask* task;

	for(;;) {
		NSAutoreleasePool* innerPool = [[NSAutoreleasePool alloc] init];

		FD_ZERO(&rfds);
		FD_ZERO(&wfds);
		FD_ZERO(&efds);

		// Unblock pipe to interrupt select() whenever a PTYTask register/unregisters
		highfd = unblockPipeR;
		FD_SET(unblockPipeR, &rfds);

		// Add all the PTYTask pipes
		iter = [tasks objectEnumerator];
		while(task = [iter nextObject]) {
			int fd = [task fd];
			if(fd < 0)
				goto breakloop;
			if(fd > highfd)
				highfd = fd;
			if([task wantsRead])
				FD_SET(fd, &rfds);
			if([task wantsWrite])
				FD_SET(fd, &wfds);
			FD_SET(fd, &efds);
		}

		// Poll...
		if(select(highfd+1, &rfds, &wfds, &efds, NULL) <= 0) {
			switch(errno) {
				case EAGAIN:
				case EINTR:
					goto breakloop;
				default:
					NSLog(@"Major fail! %s", strerror(errno));
					exit(1);
			}
		}

		// Interrupted?
		if(FD_ISSET(unblockPipeR, &rfds)) {
			do {
				char dummy[32];
				read(unblockPipeR, dummy, sizeof(dummy));
			} while(errno != EAGAIN);
		}

		// Check for read events on PTYTask pipes
		iter = [tasks objectEnumerator];
		while(task = [iter nextObject]) {
			int fd = [task fd];
			if(fd < 0)
				goto breakloop;
			if(FD_ISSET(fd, &rfds))
				[task processRead];
			if(FD_ISSET(fd, &wfds))
				[task processWrite];
			if(FD_ISSET(fd, &efds))
				[task brokenPipe];
		}

		breakloop:
		[innerPool drain];
	}

	[outerPool drain];
}

@end

@implementation PTYTask

#define CTRLKEY(c)   ((c)-'A'+1)

static void
setup_tty_param(
		struct termios* term,
		struct winsize* win,
		int width,
		int height)
{
	memset(term, 0, sizeof(struct termios));
	memset(win, 0, sizeof(struct winsize));

	term->c_iflag = ICRNL | IXON | IXANY | IMAXBEL | BRKINT;
	term->c_oflag = OPOST | ONLCR;
	term->c_cflag = CREAD | CS8 | HUPCL;
	term->c_lflag = ICANON | ISIG | IEXTEN | ECHO | ECHOE | ECHOK | ECHOKE | ECHOCTL;

	term->c_cc[VEOF]	  = CTRLKEY('D');
	term->c_cc[VEOL]	  = -1;
	term->c_cc[VEOL2]	  = -1;
	term->c_cc[VERASE]	  = 0x7f;	// DEL
	term->c_cc[VWERASE]   = CTRLKEY('W');
	term->c_cc[VKILL]	  = CTRLKEY('U');
	term->c_cc[VREPRINT]  = CTRLKEY('R');
	term->c_cc[VINTR]	  = CTRLKEY('C');
	term->c_cc[VQUIT]	  = 0x1c;	// Control+backslash
	term->c_cc[VSUSP]	  = CTRLKEY('Z');
	term->c_cc[VDSUSP]	  = CTRLKEY('Y');
	term->c_cc[VSTART]	  = CTRLKEY('Q');
	term->c_cc[VSTOP]	  = CTRLKEY('S');
	term->c_cc[VLNEXT]	  = -1;
	term->c_cc[VDISCARD]  = -1;
	term->c_cc[VMIN]	  = 1;
	term->c_cc[VTIME]	  = 0;
	term->c_cc[VSTATUS]   = -1;

	term->c_ispeed = B38400;
	term->c_ospeed = B38400;

	win->ws_row = height;
	win->ws_col = width;
	win->ws_xpixel = 0;
	win->ws_ypixel = 0;
}

- (id)init
{
#if DEBUG_ALLOC
	NSLog(@"%s: 0x%x", __PRETTY_FUNCTION__, self);
#endif
	if ([super init] == nil)
		return nil;

	pid = (pid_t)-1;
	status = 0;
	delegate = nil;
	fd = -1;
	tty = nil;
	logPath = nil;
	logHandle = nil;
	hasOutput = NO;

	writeBuffer = [[NSMutableData alloc] init];
	writeLock = [[NSLock alloc] init];

	return self;
}

- (void)dealloc
{
#if DEBUG_ALLOC
	NSLog(@"%s: 0x%x", __PRETTY_FUNCTION__, self);
#endif
	[[TaskNotifier sharedInstance] deregisterTask:self];

	if (pid > 0)
		kill(pid, SIGKILL);

	if (fd >= 0)
		close(fd);

	[writeLock release];
	[writeBuffer release];
	[tty release];
	[path release];
	[super dealloc];
}

- (void)launchWithPath:(NSString*)progpath
		arguments:(NSArray*)args environment:(NSDictionary*)env
		width:(int)width height:(int)height
{
	struct termios term;
	struct winsize win;
	char ttyname[PATH_MAX];
	int sts;

	path = [progpath copy];

#if DEBUG_METHOD_TRACE
	NSLog(@"%s(%d):-[launchWithPath:%@ arguments:%@ environment:%@ width:%d height:%d", __FILE__, __LINE__, progpath, args, env, width, height);
#endif

	setup_tty_param(&term, &win, width, height);
	pid = forkpty(&fd, ttyname, &term, &win);
	if (pid == (pid_t)0) {
		const char* argpath = [[progpath stringByStandardizingPath] cString];
		int max = args == nil ? 0: [args count];
		const char* argv[max + 2];

		argv[0] = argpath;
		if (args != nil) {
			int i;
			for (i = 0; i < max; ++i)
				argv[i + 1] = [[args objectAtIndex:i] cString];
		}
		argv[max + 1] = NULL;

		if (env != nil ) {
			NSArray* keys = [env allKeys];
			int i, max = [keys count];
			for (i = 0; i < max; ++i) {
				NSString* key;
				NSString* value;
				key = [keys objectAtIndex:i];
				value = [env objectForKey:key];
				if (key != nil && value != nil)
					setenv([key cString], [value cString], 1);
			}
		}
		chdir([[[env objectForKey:@"PWD"] stringByExpandingTildeInPath] cString]);
		sts = execvp(argpath, (char* const*)argv);

		/* exec error */
		fprintf(stdout, "## exec failed ##\n");
		fprintf(stdout, "%s %s\n", argpath, strerror(errno));

		sleep(1);
		_exit(-1);
	}
	else if (pid < (pid_t)0) {
		NSLog(@"%@ %s", progpath, strerror(errno));
		NSRunCriticalAlertPanel(NSLocalizedStringFromTableInBundle(@"Unable to Fork!",@"iTerm", [NSBundle bundleForClass: [self class]], @"Fork Error"),
						NSLocalizedStringFromTableInBundle(@"iTerm cannot launch the program for this session.",@"iTerm", [NSBundle bundleForClass: [self class]], @"Fork Error"),
						NSLocalizedStringFromTableInBundle(@"Close Session",@"iTerm", [NSBundle bundleForClass: [self class]], @"Fork Error"),
						nil,nil);
		if([delegate respondsToSelector:@selector(closeSession:)]) {
			[delegate performSelector:@selector(closeSession:) withObject:delegate];
		}
		return;
	}

	tty = [[NSString stringWithCString:ttyname] retain];
	NSParameterAssert(tty != nil);

	fcntl(fd,F_SETFL,O_NONBLOCK);
	[[TaskNotifier sharedInstance] registerTask:self];
}

- (BOOL)wantsRead
{
	return YES;
}

- (BOOL)wantsWrite
{
	return [writeBuffer length] > 0;
}

- (void)processRead
{
#if DEBUG_METHOD_TRACE
	NSLog(@"%s(%d):+[PTYTask processRead]", __FILE__, __LINE__);
#endif

	// Only write up to MAXRW bytes, then release control
	NSMutableData* data = [NSMutableData dataWithLength:MAXRW];
	ssize_t bytesread = read(fd, [data mutableBytes], MAXRW);

	// No data?
	if(bytesread < 0 && !(errno == EAGAIN || errno == EINTR)) {
		[self brokenPipe];
		return;
	}

	// Send data to the terminal
	[data setLength:bytesread];
	hasOutput = YES;
	[self readTask:data];
}

- (void)processWrite
{
#if DEBUG_METHOD_TRACE
	NSLog(@"%s(%d):-[PTYTask processWrite] with writeBuffer length %d",
			__FILE__, __LINE__, [writeBuffer length]);
#endif

	// Retain to prevent the object from being released during this method
	// Lock to protect the writeBuffer from the main thread
	[self retain];
	[writeLock lock];

	// Only write up to MAXRW bytes, then release control
	const char* ptr = [writeBuffer mutableBytes];
	unsigned int length = [writeBuffer length];
	if(length > MAXRW) length = MAXRW;
	ssize_t written = write(fd, [writeBuffer mutableBytes], length);

	// No data?
	if(written < 0 && !(errno == EAGAIN || errno == EINTR)) {
		[self brokenPipe];
		return;
	}

	// Shrink the writeBuffer
	length = [writeBuffer length] - written;
	memmove(ptr, ptr+written, length);
	[writeBuffer setLength:length];

	// Clean up locks
	[writeLock unlock];
	[self autorelease];
}

- (BOOL)hasOutput
{
	return hasOutput;
}

- (void)setDelegate:(id)object
{
	delegate = object;
}

- (id)delegate
{
	return delegate;
}

- (void)readTask:(NSData*)data
{
#if DEBUG_METHOD_TRACE
	NSLog(@"%s(%d):-[PTYTask readTask:%@]", __FILE__, __LINE__, data);
#endif
	if([self logging]) {
		[logHandle writeData:data];
	}

	// forward the data to our delegate
	if([delegate respondsToSelector:@selector(readTask:)]) {
		[delegate performSelectorOnMainThread:@selector(readTask:)
				withObject:data waitUntilDone:YES];
	}
}

- (void)writeTask:(NSData*)data
{
#if DEBUG_METHOD_TRACE
	NSLog(@"%s(%d):-[PTYTask writeTask:%@]", __FILE__, __LINE__, data);
#endif

	// Write as much as we can now through the non-blocking pipe
	// Lock to protect the writeBuffer from the IO thread
	[writeLock lock];
	[writeBuffer appendData:data];
	[[TaskNotifier sharedInstance] unblock];
	[writeLock unlock];
}

- (void)brokenPipe
{
	[[TaskNotifier sharedInstance] deregisterTask:self];
	if([delegate respondsToSelector:@selector(brokenPipe)]) {
		[delegate performSelectorOnMainThread:@selector(brokenPipe)
				withObject:nil waitUntilDone:YES];
	}
}

- (void)sendSignal:(int)signo
{
	if (pid >= 0)
		kill(pid, signo);
}

- (void)setWidth:(int)width height:(int)height
{
	struct winsize winsize;

	if(fd == -1)
		return;

	ioctl(fd, TIOCGWINSZ, &winsize);
	if (winsize.ws_col != width || winsize.ws_row != height) {
		winsize.ws_col = width;
		winsize.ws_row = height;
		ioctl(fd, TIOCSWINSZ, &winsize);
	}
}

- (int)fd
{
	return fd;
}

- (pid_t)pid
{
	return pid;
}

- (int)wait
{
	if (pid >= 0)
		waitpid(pid, &status, 0);

	return status;
}

- (void)stop
{
	[self sendSignal:SIGKILL];
	usleep(10000);
	if(fd >= 0)
		close(fd);
	fd = -1;

	[self wait];
}

- (int)status
{
	return status;
}

- (NSString*)tty
{
	return tty;
}

- (NSString*)path
{
	return path;
}

- (BOOL)loggingStartWithPath:(NSString*)aPath
{
	[logPath autorelease];
	logPath = [[aPath stringByStandardizingPath] copy];

	[logHandle autorelease];
	logHandle = [NSFileHandle fileHandleForWritingAtPath:logPath];
	if (logHandle == nil) {
		NSFileManager* fm = [NSFileManager defaultManager];
		[fm createFileAtPath:logPath contents:nil attributes:nil];
		logHandle = [NSFileHandle fileHandleForWritingAtPath:logPath];
	}
	[logHandle retain];
	[logHandle seekToEndOfFile];

	return logHandle == nil ? NO:YES;
}

- (void)loggingStop
{
	[logHandle closeFile];

	[logPath autorelease];
	[logHandle autorelease];
	logPath = nil;
	logHandle = nil;
}

- (BOOL)logging
{
	return logHandle == nil ? NO : YES;
}

- (NSString*)description
{
	return [NSString stringWithFormat:@"PTYTask(pid %d, fildes %d)", pid, fd];
}

- (NSString*)getWorkingDirectory
{
	static int loadedAttempted = 0;
	static int(*proc_pidinfo)(pid_t pid, int flavor, uint64_t arg, void* buffer, int buffersize) = NULL;
	if (!proc_pidinfo) {
		if (loadedAttempted) {
			/* Hmm, we can't find the symbols that we need... so lets not try */
			return nil;
		}
		loadedAttempted = 1;

		/* We need to load the function first */
		void* handle = dlopen("libSystem.B.dylib", RTLD_LAZY);
		if (!handle)
			return nil;
		proc_pidinfo = dlsym(handle, "proc_pidinfo");
		if (!proc_pidinfo)
			return nil;
	}

	struct proc_vnodepathinfo vpi;
	int ret;
	/* This only works if the child process is owned by our uid */
	ret = proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &vpi, sizeof(vpi));
	if (ret <= 0) {
		/* An error occured */
		return nil;
	} else if (ret != sizeof(vpi)) {
		/* Now this is very bad... */
		return nil;
	} else {
		/* All is good */
		NSString* ret = [NSString stringWithUTF8String:vpi.pvi_cdir.vip_path];
		return ret;
	}
}

@end

