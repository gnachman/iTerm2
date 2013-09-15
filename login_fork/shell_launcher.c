/*-
 * Copyright (c) 1980, 1987, 1988, 1991, 1993, 1994
 *	The Regents of the University of California.  All rights reserved.
 * Copyright (c) 2002 Networks Associates Technologies, Inc.
 * All rights reserved.
 *
 * Portions of this software were developed for the FreeBSD Project by
 * ThinkSec AS and NAI Labs, the Security Research Division of Network
 * Associates, Inc.  under DARPA/SPAWAR contract N66001-01-C-8035
 * ("CBOSS"), as part of the DARPA CHATS research program.
 * Portions copyright (c) 1999-2007 Apple Inc.  All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 * 1. Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 * 2. Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 * 3. All advertising materials mentioning features or use of this software
 *    must display the following acknowledgement:
 *	This product includes software developed by the University of
 *	California, Berkeley and its contributors.
 * 4. Neither the name of the University nor the names of its contributors
 *    may be used to endorse or promote products derived from this software
 *    without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE REGENTS AND CONTRIBUTORS ``AS IS'' AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED.  IN NO EVENT SHALL THE REGENTS OR CONTRIBUTORS BE LIABLE
 * FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
 * OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
 * LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
 * OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
 * SUCH DAMAGE.
 */

// This is a massively stripped-down version of login. All it does is launch the shell, sticking
// a - at the start of argv[0] to make it think it's a login shell. Unfortunately, Apple's
// login(1) doesn't let you preseve the working directory and also start a login shell, which iTerm2
// needs to be able to do. This is meant to be run this way:
//   login -fpl $USER shell_launcher

#include <paths.h>
#include <sys/param.h>
#include <err.h>
#include <errno.h>
#include <util.h>
#include <signal.h>
#include <stdlib.h>
#include <string.h>
#include <syslog.h>
#include <unistd.h>


static void handle_sighup(int signo);

static char *username;	/* user name */
static pid_t pid;

int main(int argc, char *argv[])
{
	char *arg0;
	const char *shell = NULL;

	username = getenv("USER");
    shell = getenv("SHELL");
    
	(void)signal(SIGQUIT, SIG_IGN);
	(void)signal(SIGINT, SIG_IGN);
	/* Install a signal handler that will forward SIGHUP to the
	   child and process group.  The parent should not exit on
	   SIGHUP so that the tty ownership can be reset. */
	(void)signal(SIGHUP, handle_sighup);

	/*
	 * We must fork() before setuid() because we need to call
	 * pam_close_session() as root.
	 */
	pid = fork();
	if (pid < 0) {
		err(1, "fork");
	} else if (pid != 0) {
		/*
		 * Parent: wait for child to finish, then clean up
		 * session.
		 */
		int status;
		/* Our SIGHUP handler may interrupt the wait */
		int res;
		do {
			res = waitpid(pid, &status, 0);
		} while (res == -1 && errno == EINTR);
		waitpid(pid, &status, 0);
        exit(0);
	}
    
    /* Restore the default SIGHUP handler for the child. */
	(void)signal(SIGHUP, SIG_DFL);
	(void)signal(SIGQUIT, SIG_DFL);
	(void)signal(SIGINT, SIG_DFL);
	(void)signal(SIGTSTP, SIG_IGN);

	/*
	 * Login shells have a leading '-' in front of argv[0]
	 */
	char *p = strrchr(shell, '/');
	if (asprintf(&arg0, "-%s", p ? p + 1 : shell) >= MAXPATHLEN) {
		errx(1, "shell exceeds maximum pathname size");
	} else if (arg0 == NULL) {
		err(1, "asprintf()");
	}

    execlp(shell, arg0, (char*)0);
	err(1, "%s", shell);
}


/*
 * SIGHUP handler
 * Forwards the SIGHUP to the child process and current process group.
 */
static void
handle_sighup(int signo)
{
	if (pid > 0) {
		/* close the controlling terminal */
		close(STDIN_FILENO);
		close(STDOUT_FILENO);
		close(STDERR_FILENO);
		/* Ignore SIGHUP to avoid tail-recursion on signaling
         the current process group (of which we are a member). */
		(void)signal(SIGHUP, SIG_IGN);
		/* Forward the signal to the current process group. */
		(void)kill(0, signo);
		/* Forward the signal to the child if not a member of the current
		 * process group <rdar://problem/6244808>. */
		if (getpgid(pid) != getpgrp()) {
			(void)kill(pid, signo);
		}
	}
}
