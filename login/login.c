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

#if 0
#ifndef lint
static char sccsid[] = "@(#)login.c	8.4 (Berkeley) 4/2/94";
#endif
#endif

#include <sys/cdefs.h>
__FBSDID("$FreeBSD: src/usr.bin/login/login.c,v 1.106 2007/07/04 00:00:40 scf Exp $");

/*
 * login [ name ]
 * login -h hostname	(for telnetd, etc.)
 * login -f name	(for pre-authenticated login: datakit, xterm, etc.)
 */

#ifndef __APPLE__
#include <sys/copyright.h>
#endif
#ifdef __APPLE__
#include <TargetConditionals.h>
#endif
#include <sys/param.h>
#include <sys/file.h>
#include <sys/stat.h>
#include <sys/time.h>
#include <sys/resource.h>
#include <sys/wait.h>

#include <err.h>
#include <errno.h>
#include <grp.h>
#ifdef __APPLE__
#include <util.h>
#else
#include <libutil.h>
#endif
#ifdef LOGIN_CAP
#include <login_cap.h>
#endif
#include <pwd.h>
#include <setjmp.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <syslog.h>
#include <ttyent.h>
#include <unistd.h>
#ifdef __APPLE__
#include <utmpx.h>
#ifdef USE_PAM
#else /* !USE_PAM */
#ifndef _UTX_USERSIZE
#define _UTX_USERSIZE MAXLOGNAME
#endif
#endif /* USE_PAM */
#endif /* __APPLE__ */

#include <sys/types.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <netdb.h>

#ifdef USE_BSM_AUDIT
#include <bsm/libbsm.h>
#include <bsm/audit.h>
#include <bsm/audit_session.h>
#include <bsm/audit_uevents.h>
#endif

#ifdef __APPLE__
#include <mach/mach_types.h>
#include <mach/task.h>
#include <mach/mach_init.h>
#include <servers/bootstrap.h>

#include <sys/file.h>
#include <tzfile.h>
#endif /* __APPLE__ */

#ifdef USE_PAM
#include <security/pam_appl.h>
#include <security/openpam.h>
#endif /* USE_PAM */

#include "login.h"
#include "pathnames.h"

#ifdef USE_PAM
static int		 auth_pam(int skip_auth);
#endif /* USE_PAM */
static void		 bail(int, int);
#ifdef USE_PAM
static int		 export(const char *);
static void		 export_pam_environment(void);
#endif /* USE_PAM */
static int		 motd(const char *);
static void		 badlogin(char *);
static char		*getloginname(void);
#ifdef USE_PAM
static void		 pam_syslog(const char *);
static void		 pam_cleanup(void);
#endif /* USE_PAM */
static void		 refused(const char *, const char *, int);
static const char	*stypeof(char *);
static void		 sigint(int);
static void		 timedout(int);
static void		 usage(void);

#ifdef __APPLE__
static void		 dolastlog(int);
static void		 handle_sighup(int);

#ifndef USE_PAM
static void		 checknologin(void);
static int		 rootterm(const char *);
#endif /* !USE_PAM */
#endif /* __APPLE__ */

#define	TTYGRPNAME		"tty"			/* group to own ttys */
#define	DEFAULT_BACKOFF		3
#define	DEFAULT_RETRIES		10
#define	DEFAULT_PROMPT		"login: "
#define	DEFAULT_PASSWD_PROMPT	"Password:"
#define	TERM_UNKNOWN		"su"
#define	DEFAULT_WARN		(2L * 7L * 86400L)	/* Two weeks */
#define NO_SLEEP_EXIT		0
#define SLEEP_EXIT		5

/*
 * This bounds the time given to login.  Not a define so it can
 * be patched on machines where it's too small.
 */
static u_int		timeout = 300;

/* Buffer for signal handling of timeout */
static jmp_buf		 timeout_buf;

struct passwd		*pwd;
static int		 failures;

static char		*envinit[1];	/* empty environment list */

/*
 * Command line flags and arguments
 */
static int		 fflag;		/* -f: do not perform authentication */
#ifdef __APPLE__
static int		 lflag;		/*   -l: login session to the commmand that follows username */
#endif
static int		 hflag;		/* -h: login from remote host */
static char		*hostname;	/* hostname from command line */
static int		 pflag;		/* -p: preserve environment */

/*
 * User name
 */
static char		*username;	/* user name */
static char		*olduser;	/* previous user name */

/*
 * Prompts
 */
static char		 default_prompt[] = DEFAULT_PROMPT;
static const char	*prompt;
static char		 default_passwd_prompt[] = DEFAULT_PASSWD_PROMPT;
static const char	*passwd_prompt;

static char		*tty;

/*
 * PAM data
 */
#ifdef USE_PAM
static pam_handle_t	*pamh = NULL;
static struct pam_conv	 pamc = { openpam_ttyconv, NULL };
static int		 pam_err;
static int		 pam_silent = PAM_SILENT;
static int		 pam_cred_established;
static int		 pam_session_established;
#endif /* USE_PAM */

#ifdef __APPLE__
pid_t pid;

#ifdef USE_PAM
static struct lastlogx lastlog;
#endif /* USE_PAM */

#ifdef USE_BSM_AUDIT
extern au_tid_addr_t tid;
#endif /* USE_BSM_AUDIT */
#endif /* __APPLE__ */

int
main(int argc, char *argv[])
{
	struct group *gr;
	struct stat st;
	int retries, backoff;
	int ask, ch, cnt, quietlog = 0, rootlogin, rval;
	uid_t uid, euid;
	gid_t egid;
	char *term;
	char *p, *ttyn;
	char tname[sizeof(_PATH_TTY) + 10];
	char *arg0;
	const char *tp;
#ifdef __APPLE__
	int prio;
#ifdef USE_PAM
	const char *name = "login";	/* PAM config */
#else
	struct utmpx utmp;
#endif /* USE_PAM */
	const char *shell = NULL;
#endif /* !__APPLE__ */
#ifdef LOGIN_CAP
	login_cap_t *lc = NULL;
	login_cap_t *lc_user = NULL;
#endif /* LOGIN_CAP */
#ifndef __APPLE__
	pid_t pid;
#endif
#ifdef USE_BSM_AUDIT
	char auditsuccess = 1;
#endif

	(void)signal(SIGQUIT, SIG_IGN);
	(void)signal(SIGINT, SIG_IGN);
	(void)signal(SIGHUP, SIG_IGN);
	if (setjmp(timeout_buf)) {
		if (failures)
			badlogin(username);
		(void)fprintf(stderr, "Login timed out after %d seconds\n",
		    timeout);
		bail(NO_SLEEP_EXIT, 0);
	}
	(void)signal(SIGALRM, timedout);
	(void)alarm(timeout);
#ifdef __APPLE__
	prio = getpriority(PRIO_PROCESS, 0);
#endif
	(void)setpriority(PRIO_PROCESS, 0, 0);

	openlog("login", LOG_ODELAY, LOG_AUTH);

	uid = getuid();
	euid = geteuid();
	egid = getegid();

#ifdef __APPLE__
	while ((ch = getopt(argc, argv, "1fh:lpq")) != -1)
#else
	while ((ch = getopt(argc, argv, "fh:p")) != -1)
#endif
		switch (ch) {
		case 'f':
			fflag = 1;
			break;
		case 'h':
			if (uid != 0)
				errx(1, "-h option: %s", strerror(EPERM));
			if (strlen(optarg) >= MAXHOSTNAMELEN)
				errx(1, "-h option: %s: exceeds maximum "
				    "hostname size", optarg);
			hflag = 1;
			hostname = optarg;
			break;
		case 'p':
			pflag = 1;
			break;
#ifdef __APPLE__
		case '1':
			break;
		case 'l':
			lflag = 1;
			break;
		case 'q':
			quietlog = 1;
			break;
#endif
		case '?':
		default:
			if (uid == 0)
				syslog(LOG_ERR, "invalid flag %c", ch);
			usage();
		}
	argc -= optind;
	argv += optind;

	if (argc > 0) {
		username = strdup(*argv);
		if (username == NULL)
			err(1, "strdup()");
		ask = 0;
#ifdef __APPLE__
		argv++;
#endif /* __APPLE__ */
	} else {
		ask = 1;
	}

#ifndef __APPLE__
	setproctitle("-%s", getprogname());
#endif /* !__APPLE__ */

	for (cnt = getdtablesize(); cnt > 2; cnt--)
		(void)close(cnt);

	/*
	 * Get current TTY
	 */
	ttyn = ttyname(STDIN_FILENO);
	if (ttyn == NULL || *ttyn == '\0') {
		(void)snprintf(tname, sizeof(tname), "%s??", _PATH_TTY);
		ttyn = tname;
	}
	if ((tty = strrchr(ttyn, '/')) != NULL)
		++tty;
	else
		tty = ttyn;

#ifdef LOGIN_CAP
	/*
	 * Get "login-retries" & "login-backoff" from default class
	 */
	lc = login_getclass(NULL);
	prompt = login_getcapstr(lc, "login_prompt",
	    default_prompt, default_prompt);
	passwd_prompt = login_getcapstr(lc, "passwd_prompt",
	    default_passwd_prompt, default_passwd_prompt);
	retries = login_getcapnum(lc, "login-retries",
	    DEFAULT_RETRIES, DEFAULT_RETRIES);
	backoff = login_getcapnum(lc, "login-backoff",
	    DEFAULT_BACKOFF, DEFAULT_BACKOFF);
	login_close(lc);
	lc = NULL;
#else /* !LOGIN_CAP */
	prompt = default_prompt;
	passwd_prompt = default_passwd_prompt;
	retries = DEFAULT_RETRIES;
	backoff = DEFAULT_BACKOFF;
#endif /* !LOGIN_CAP */

#ifdef __APPLE__
#ifdef USE_BSM_AUDIT
	/* Set the terminal id */
	au_tid_t old_tid;
	audit_set_terminal_id(&old_tid);
	tid.at_type = AU_IPv4;
	tid.at_addr[0] = old_tid.machine;
	if (fstat(STDIN_FILENO, &st) < 0) {
		fprintf(stderr, "login: Unable to stat terminal\n");
		au_login_fail("Unable to stat terminal", 1);
		exit(-1);
	}
	if (S_ISCHR(st.st_mode)) {
		tid.at_port = st.st_rdev;
	} else {
		tid.at_port = 0;
	}
#endif /* USE_BSM_AUDIT */
#endif /* __APPLE__ */

	/*
	 * Try to authenticate the user until we succeed or time out.
	 */
	for (cnt = 0;; ask = 1) {
		if (ask) {
			fflag = 0;
			if (olduser != NULL)
				free(olduser);
			olduser = username;
			username = getloginname();
		}
		rootlogin = 0;

#ifdef __APPLE__
		if (strlen(username) > _UTX_USERSIZE)
			username[_UTX_USERSIZE] = '\0';
#endif /* __APPLE__ */

		/*
		 * Note if trying multiple user names; log failures for
		 * previous user name, but don't bother logging one failure
		 * for nonexistent name (mistyped username).
		 */
		if (failures && strcmp(olduser, username) != 0) {
			if (failures > (pwd ? 0 : 1))
				badlogin(olduser);
		}

#ifdef __APPLE__
#ifdef USE_PAM
	/* get lastlog info before PAM make a new entry */
	if (!quietlog)
		getlastlogxbyname(username, &lastlog);
#endif /* USE_PAM */
#endif /* __APPLE__ */

		pwd = getpwnam(username);

#ifdef USE_PAM
		/*
		 * Load the PAM policy and set some variables
		 */
#ifdef __APPLE__
		if (fflag && (pwd != NULL) && (pwd->pw_uid == uid)) {
			name = "login.term";
		}
#endif
		pam_err = pam_start(name, username, &pamc, &pamh);
		if (pam_err != PAM_SUCCESS) {
			pam_syslog("pam_start()");
#ifdef USE_BSM_AUDIT
			au_login_fail("PAM Error", 1);
#endif
			bail(NO_SLEEP_EXIT, 1);
		}
		pam_err = pam_set_item(pamh, PAM_TTY, tty);
		if (pam_err != PAM_SUCCESS) {
			pam_syslog("pam_set_item(PAM_TTY)");
#ifdef USE_BSM_AUDIT
			au_login_fail("PAM Error", 1);
#endif
			bail(NO_SLEEP_EXIT, 1);
		}
		pam_err = pam_set_item(pamh, PAM_RHOST, hostname);
		if (pam_err != PAM_SUCCESS) {
			pam_syslog("pam_set_item(PAM_RHOST)");
#ifdef USE_BSM_AUDIT
			au_login_fail("PAM Error", 1);
#endif
			bail(NO_SLEEP_EXIT, 1);
		}
#endif /* USE_PAM */

		if (pwd != NULL && pwd->pw_uid == 0)
			rootlogin = 1;

		/*
		 * If the -f option was specified and the caller is
		 * root or the caller isn't changing their uid, don't
		 * authenticate.
		 */
		if (pwd != NULL && fflag &&
		    (uid == (uid_t)0 || uid == (uid_t)pwd->pw_uid)) {
#ifdef USE_PAM
			rval = auth_pam(fflag);
#else
			rval = 0;
#endif /* USE_PAM */
#ifdef USE_BSM_AUDIT
			auditsuccess = 0; /* opened a terminal window only */
#endif

#ifdef __APPLE__
#ifndef USE_PAM
		/* If the account doesn't have a password, authenticate. */
		} else if (pwd != NULL && pwd->pw_passwd[0] == '\0') {
			rval = 0;
#endif /* !USE_PAM */
#endif /* __APPLE__ */
		} else if( pwd ) {
			fflag = 0;
			(void)setpriority(PRIO_PROCESS, 0, -4);
#ifdef USE_PAM
			rval = auth_pam(fflag);
#else
		{
			char* salt = pwd->pw_passwd;
			char* p = getpass(passwd_prompt);
			rval = strcmp(crypt(p, salt), salt);
			memset(p, 0, strlen(p));
		}
#endif
			(void)setpriority(PRIO_PROCESS, 0, 0);
		} else {
			rval = -1;
		}

#ifdef __APPLE__
#ifndef USE_PAM
		/*
		 * If trying to log in as root but with insecure terminal,
		 * refuse the login attempt.
		 */
		if (pwd && rootlogin && !rootterm(tty)) {
			refused("root login refused on this terminal", "ROOTTERM", 0);
#ifdef USE_BSM_AUDIT
			au_login_fail("Login refused on terminal", 0);
#endif
			continue;
		}
#endif /* !USE_PAM */
#endif /* __APPLE__ */

		if (pwd && rval == 0)
			break;

#ifdef USE_PAM
		pam_cleanup();
#endif /* USE_PAM */

		/*
		 * We are not exiting here, but this corresponds to a failed
		 * login event, so set exitstatus to 1.
		 */
#ifdef USE_BSM_AUDIT
		au_login_fail("Login incorrect", 1);
#endif

		(void)printf("Login incorrect\n");
		failures++;

		pwd = NULL;

		/*
		 * Allow up to 'retry' (10) attempts, but start
		 * backing off after 'backoff' (3) attempts.
		 */
		if (++cnt > backoff) {
			if (cnt >= retries) {
				badlogin(username);
				bail(SLEEP_EXIT, 1);
			}
			sleep((u_int)((cnt - backoff) * 5));
		}
	}

	/* committed to login -- turn off timeout */
	(void)alarm((u_int)0);
	(void)signal(SIGHUP, SIG_DFL);

	endpwent();

#ifdef __APPLE__
	if (!pwd) {
		fprintf(stderr, "login: Unable to find user: %s\n", username);
		exit(1);
	}

#ifndef USE_PAM
	/* if user not super-user, check for disabled logins */
	if (!rootlogin)
		checknologin();
#endif /* !USE_PAM */
#endif /* APPLE */

#ifdef USE_BSM_AUDIT
	/* Audit successful login. */
	if (auditsuccess)
		au_login_success(fflag);
#endif

#ifdef LOGIN_CAP
	/*
	 * Establish the login class.
	 */
	lc = login_getpwclass(pwd);
	lc_user = login_getuserclass(pwd);

	if (!(quietlog = login_getcapbool(lc_user, "hushlogin", 0)))
		quietlog = login_getcapbool(lc, "hushlogin", 0);
#endif /* LOGIN_CAP */

#ifndef __APPLE__
	/*
	 * Switching needed for NFS with root access disabled.
	 *
	 * XXX: This change fails to modify the additional groups for the
	 * process, and as such, may restrict rights normally granted
	 * through those groups.
	 */
	(void)setegid(pwd->pw_gid);
	(void)seteuid(rootlogin ? 0 : pwd->pw_uid);

	if (!*pwd->pw_dir || chdir(pwd->pw_dir) < 0) {
#ifdef LOGIN_CAP
		if (login_getcapbool(lc, "requirehome", 0))
			refused("Home directory not available", "HOMEDIR", 1);
#endif /* LOGIN_CAP */
		if (chdir("/") < 0)
			refused("Cannot find root directory", "ROOTDIR", 1);
		if (!quietlog || *pwd->pw_dir)
			printf("No home directory.\nLogging in with home = \"/\".\n");
		pwd->pw_dir = strdup("/");
		if (pwd->pw_dir == NULL) {
			syslog(LOG_NOTICE, "strdup(): %m");
			bail(SLEEP_EXIT, 1);
		}
	}

	(void)seteuid(euid);
	(void)setegid(egid);
#endif /* !__APPLE__ */
	if (!quietlog) {
		quietlog = access(_PATH_HUSHLOGIN, F_OK) == 0;
#ifdef USE_PAM
		if (!quietlog)
			pam_silent = 0;
#endif /* USE_PAM */
	}

#ifdef __APPLE__
	/* Nothing else left to fail -- really log in. */
#ifndef USE_PAM
	memset((void *)&utmp, 0, sizeof(utmp));
	(void)gettimeofday(&utmp.ut_tv, NULL);
	(void)strncpy(utmp.ut_user, username, sizeof(utmp.ut_user));
	if (hostname)
		(void)strncpy(utmp.ut_host, hostname, sizeof(utmp.ut_host));
	(void)strncpy(utmp.ut_line, tty, sizeof(utmp.ut_line));
	utmp.ut_type = USER_PROCESS | UTMPX_AUTOFILL_MASK;
	utmp.ut_pid = getpid();
	pututxline(&utmp);
#endif /* USE_PAM */

	shell = "";
#endif /* !__APPLE__ */
#ifdef LOGIN_CAP
	shell = login_getcapstr(lc, "shell", pwd->pw_shell, pwd->pw_shell);
#endif /* !LOGIN_CAP */
	if (*pwd->pw_shell == '\0')
		pwd->pw_shell = strdup(_PATH_BSHELL);
	if (pwd->pw_shell == NULL) {
		syslog(LOG_NOTICE, "strdup(): %m");
		bail(SLEEP_EXIT, 1);
	}

#if defined(__APPLE__) && TARGET_OS_EMBEDDED
	/* on embedded, allow a shell to live in /var/debug_mount/bin/sh */
#define _PATH_DEBUGSHELL	"/var/debug_mount/bin/sh"
        if (stat(pwd->pw_shell, &st) != 0) {
        	if (stat(_PATH_DEBUGSHELL, &st) == 0) {
        		pwd->pw_shell = strdup(_PATH_DEBUGSHELL);
        	}
        }
#endif

	if (*shell == '\0')   /* Not overridden */
		shell = pwd->pw_shell;
	if ((shell = strdup(shell)) == NULL) {
		syslog(LOG_NOTICE, "strdup(): %m");
		bail(SLEEP_EXIT, 1);
	}

#ifdef __APPLE__
	dolastlog(quietlog);
#endif

#ifndef __APPLE__
	/*
	 * Set device protections, depending on what terminal the
	 * user is logged in. This feature is used on Suns to give
	 * console users better privacy.
	 */
	login_fbtab(tty, pwd->pw_uid, pwd->pw_gid);
#endif /* !__APPLE__ */

	/*
	 * Clear flags of the tty.  None should be set, and when the
	 * user sets them otherwise, this can cause the chown to fail.
	 * Since it isn't clear that flags are useful on character
	 * devices, we just clear them.
	 *
	 * We don't log in the case of EOPNOTSUPP because dev might be
	 * on NFS, which doesn't support chflags.
	 *
	 * We don't log in the EROFS because that means that /dev is on
	 * a read only file system and we assume that the permissions there
	 * are sane.
	 */
	if (ttyn != tname && chflags(ttyn, 0))
#ifdef __APPLE__
		if (errno != EOPNOTSUPP && errno != ENOTSUP && errno != EROFS)
#else
		if (errno != EOPNOTSUPP && errno != EROFS)
#endif
			syslog(LOG_ERR, "chflags(%s): %m", ttyn);
	if (ttyn != tname && chown(ttyn, pwd->pw_uid,
	    (gr = getgrnam(TTYGRPNAME)) ? gr->gr_gid : pwd->pw_gid))
		if (errno != EROFS)
			syslog(LOG_ERR, "chown(%s): %m", ttyn);

#ifdef __APPLE__
	(void)chmod(ttyn, 0620);
#endif /* __APPLE__ */

#ifndef __APPLE__
	/*
	 * Exclude cons/vt/ptys only, assume dialup otherwise
	 * TODO: Make dialup tty determination a library call
	 * for consistency (finger etc.)
	 */
	if (hflag && isdialuptty(tty))
		syslog(LOG_INFO, "DIALUP %s, %s", tty, pwd->pw_name);
#endif /* !__APPLE__ */

#ifdef LOGALL
	/*
	 * Syslog each successful login, so we don't have to watch
	 * hundreds of wtmp or lastlogin files.
	 */
	if (hflag)
		syslog(LOG_INFO, "login from %s on %s as %s",
		       hostname, tty, pwd->pw_name);
	else
		syslog(LOG_INFO, "login on %s as %s",
		       tty, pwd->pw_name);
#endif

	/*
	 * If fflag is on, assume caller/authenticator has logged root
	 * login.
	 */
	if (rootlogin && fflag == 0) {
		if (hflag)
			syslog(LOG_NOTICE, "ROOT LOGIN (%s) ON %s FROM %s",
			    username, tty, hostname);
		else
			syslog(LOG_NOTICE, "ROOT LOGIN (%s) ON %s",
			    username, tty);
	}

	/*
	 * Destroy environment unless user has requested its
	 * preservation - but preserve TERM in all cases
	 */
	term = getenv("TERM");
	if (!pflag)
		environ = envinit;
	if (term != NULL)
		setenv("TERM", term, 0);

#ifndef __APPLE__
	/*
	 * PAM modules might add supplementary groups during pam_setcred().
	 */
	if (setusercontext(lc, pwd, pwd->pw_uid, LOGIN_SETGROUP) != 0) {
		syslog(LOG_ERR, "setusercontext() failed - exiting");
		bail(NO_SLEEP_EXIT, 1);
	}
#endif /* !__APPLE__ */
#ifdef USE_PAM
	if (!fflag) {
		pam_err = pam_setcred(pamh, pam_silent|PAM_ESTABLISH_CRED);
		if (pam_err != PAM_SUCCESS) {
			pam_syslog("pam_setcred()");
			bail(NO_SLEEP_EXIT, 1);
		}
		pam_cred_established = 1;
	}

	pam_err = pam_open_session(pamh, pam_silent);
	if (pam_err != PAM_SUCCESS) {
		pam_syslog("pam_open_session()");
		bail(NO_SLEEP_EXIT, 1);
	}
	pam_session_established = 1;
#endif /* USE_PAM */

#ifdef __APPLE__
	/* <rdar://problem/5377791>
	   Install a signal handler that will forward SIGHUP to the
	   child and process group.  The parent should not exit on
	   SIGHUP so that the tty ownership can be reset. */
	(void)signal(SIGHUP, handle_sighup);
#endif /* __APPLE__ */

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
#ifndef __APPLE__
		setproctitle("-%s [pam]", getprogname());
#endif /* !__APPLE__ */
#ifdef __APPLE__
		/* Our SIGHUP handler may interrupt the wait */
		int res;
		do {
			res = waitpid(pid, &status, 0);
		} while (res == -1 && errno == EINTR);
#else
		waitpid(pid, &status, 0);
#endif
#ifdef __APPLE__
		chown(ttyn, 0, 0);
		chmod(ttyn, 0666);
#endif /* __APPLE__ */
		bail(NO_SLEEP_EXIT, 0);
	}

	/*
	 * NOTICE: We are now in the child process!
	 */

#ifdef __APPLE__
	/* Restore the default SIGHUP handler for the child. */
	(void)signal(SIGHUP, SIG_DFL);
#endif /* __APPLE__ */

#ifdef USE_PAM
	/*
	 * Add any environment variables the PAM modules may have set.
	 */
	export_pam_environment();

	/*
	 * We're done with PAM now; our parent will deal with the rest.
	 */
	pam_end(pamh, 0);
	pamh = NULL;
#endif /* USE_PAM */

	/*
	 * We don't need to be root anymore, so set the login name and
	 * the UID.
	 */
	if (setlogin(username) != 0) {
		syslog(LOG_ERR, "setlogin(%s): %m - exiting", username);
		bail(NO_SLEEP_EXIT, 1);
	}
#ifdef __APPLE__
	/* <rdar://problem/6041650> restore process priority if not changing uids */
	if (uid == (uid_t)pwd->pw_uid) {
		(void)setpriority(PRIO_PROCESS, 0, prio);
	}

	(void)setgid(pwd->pw_gid);
	if (initgroups(username, pwd->pw_gid) == -1)
		syslog(LOG_ERR, "login: initgroups() failed");
	(void) setuid(rootlogin ? 0 : pwd->pw_uid);		
#else /* !__APPLE__ */
	if (setusercontext(lc, pwd, pwd->pw_uid,
	    LOGIN_SETALL & ~(LOGIN_SETLOGIN|LOGIN_SETGROUP)) != 0) {
		syslog(LOG_ERR, "setusercontext() failed - exiting");
		exit(1);
	}
#endif /* !__APPLE__ */

#ifdef __APPLE__
	/* We test for the home directory after pam_open_session(3)
	 * as the home directory may have been mounted by a session
	 * module, and after changing uid as the home directory may
	 * be NFS with root access disabled. */
	if (!lflag) {
		/* First do a stat in case the homedir is automounted */
		stat(pwd->pw_dir,&st);
		if (!*pwd->pw_dir || chdir(pwd->pw_dir) < 0) {
			printf("No home directory: %s\n", pwd->pw_dir);
			if (chdir("/") < 0) {
				refused("Cannot find root directory", "ROOTDIR", 0);
				exit(1);
			}
			pwd->pw_dir = strdup("/");
			if (pwd->pw_dir == NULL) {
				syslog(LOG_NOTICE, "strdup(): %m");
				exit(1);
			}
		}
	}
#endif /* __APPLE__ */
	if (pwd->pw_shell) {
		(void)setenv("SHELL", pwd->pw_shell, 1);
	} else {
		syslog(LOG_ERR, "pwd->pw_shell not set - exiting");
		bail(NO_SLEEP_EXIT, 1);
	}
	if (pwd->pw_dir) {
		(void)setenv("HOME", pwd->pw_dir, 1);
	} else {
		(void)setenv("HOME", "/", 1);
	}
	/* Overwrite "term" from login.conf(5) for any known TERM */
	if (term == NULL && (tp = stypeof(tty)) != NULL)
		(void)setenv("TERM", tp, 1);
	else
		(void)setenv("TERM", TERM_UNKNOWN, 0);
	(void)setenv("LOGNAME", username, 1);
	(void)setenv("USER", username, 1);
	(void)setenv("PATH", rootlogin ? _PATH_STDPATH : _PATH_DEFPATH, 0);

#ifdef __APPLE__
	/* Re-enable crash reporter */
	do {
		kern_return_t kr;
		mach_port_t bp, ep, mts;
		thread_state_flavor_t flavor = 0;

#if defined(__ppc__)
		flavor = PPC_THREAD_STATE64;
#elif defined(__i386__) || defined(__x86_64__)
		flavor = x86_THREAD_STATE;
#elif defined(__arm__)
		flavor = ARM_THREAD_STATE;
#else
#error unsupported architecture
#endif

		mts = mach_task_self();

		kr = task_get_bootstrap_port(mts, &bp);
		if (kr != KERN_SUCCESS) {
		  syslog(LOG_ERR, "task_get_bootstrap_port() failure: %s (%d)",
			bootstrap_strerror(kr), kr);
		  break;
		}

		const char* bs = "com.apple.ReportCrash";
		kr = bootstrap_look_up(bp, (char*)bs, &ep);
		if (kr != KERN_SUCCESS) {
		  syslog(LOG_ERR, "bootstrap_look_up(%s) failure: %s (%d)",
			bs, bootstrap_strerror(kr), kr);
		  break;
		}

		kr = task_set_exception_ports(mts, EXC_MASK_CRASH, ep, EXCEPTION_STATE_IDENTITY | MACH_EXCEPTION_CODES, flavor);
		if (kr != KERN_SUCCESS) {
		  syslog(LOG_ERR, "task_set_exception_ports() failure: %d", kr);
		  break;
		}
	} while (0);
#endif /* __APPLE__ */

	if (!quietlog) {
#ifdef LOGIN_CAP
		const char *cw;

		cw = login_getcapstr(lc, "copyright", NULL, NULL);
		if (cw == NULL || motd(cw) == -1)
			(void)printf("%s", copyright);

		(void)printf("\n");

		cw = login_getcapstr(lc, "welcome", NULL, NULL);
		if (cw != NULL && access(cw, F_OK) == 0)
			motd(cw);
		else
			motd(_PATH_MOTDFILE);

		if (login_getcapbool(lc_user, "nocheckmail", 0) == 0 &&
		    login_getcapbool(lc, "nocheckmail", 0) == 0) {
#else /* !LOGIN_CAP */
		motd(_PATH_MOTDFILE);
		{
#endif /* !LOGIN_CAP */
			char *cx;

			/* $MAIL may have been set by class. */
			cx = getenv("MAIL");
			if (cx == NULL) {
				asprintf(&cx, "%s/%s",
				    _PATH_MAILDIR, pwd->pw_name);
			}
			if (cx && stat(cx, &st) == 0 && st.st_size != 0)
				(void)printf("You have %smail.\n",
				    (st.st_mtime > st.st_atime) ? "new " : "");
			if (getenv("MAIL") == NULL)
				free(cx);
		}
	}

#ifdef LOGIN_CAP
	login_close(lc_user);
	login_close(lc);
#endif /* LOGIN_CAP */

	(void)signal(SIGALRM, SIG_DFL);
	(void)signal(SIGQUIT, SIG_DFL);
	(void)signal(SIGINT, SIG_DFL);
	(void)signal(SIGTSTP, SIG_IGN);

#ifdef __APPLE__
	if (fflag && *argv) pwd->pw_shell = *argv;
#endif /* __APPLE__ */

	/*
	 * Login shells have a leading '-' in front of argv[0]
	 */
	p = strrchr(pwd->pw_shell, '/');
#ifdef __APPLE__
	if (asprintf(&arg0, "%s%s", lflag ? "" : "-", p ? p + 1 : pwd->pw_shell) >= MAXPATHLEN) {
#else /* __APPLE__ */
	if (asprintf(&arg0, "-%s", p ? p + 1 : pwd->pw_shell) >= MAXPATHLEN) {
#endif /* __APPLE__ */
		syslog(LOG_ERR, "user: %s: shell exceeds maximum pathname size",
		    username);
		errx(1, "shell exceeds maximum pathname size");
	} else if (arg0 == NULL) {
		err(1, "asprintf()");
	}

#ifdef __APPLE__
	if (fflag && *argv) {
		*argv = arg0;
		execvp(pwd->pw_shell, argv);
		err(1, "%s", arg0);
	}
#endif /* __APPLE__ */
	execlp(shell, arg0, (char *)0);
	err(1, "%s", shell);

	/*
	 * That's it, folks!
	 */
}

#ifdef USE_PAM
/*
 * Attempt to authenticate the user using PAM.  Returns 0 if the user is
 * authenticated, or 1 if not authenticated.  If some sort of PAM system
 * error occurs (e.g., the "/etc/pam.conf" file is missing) then this
 * function returns -1.  This can be used as an indication that we should
 * fall back to a different authentication mechanism.
 */
static int
auth_pam(int skip_auth)
{
	const char *tmpl_user;
	const void *item;
	int rval;

	rval = 0;
	
	if (skip_auth == 0)
	{
		pam_err = pam_authenticate(pamh, pam_silent);
		switch (pam_err) {

		case PAM_SUCCESS:
			/*
			 * With PAM we support the concept of a "template"
			 * user.  The user enters a login name which is
			 * authenticated by PAM, usually via a remote service
			 * such as RADIUS or TACACS+.  If authentication
			 * succeeds, a different but related "template" name
			 * is used for setting the credentials, shell, and
			 * home directory.  The name the user enters need only
			 * exist on the remote authentication server, but the
			 * template name must be present in the local password
			 * database.
			 *
			 * This is supported by two various mechanisms in the
			 * individual modules.  However, from the application's
			 * point of view, the template user is always passed
			 * back as a changed value of the PAM_USER item.
			 */
			pam_err = pam_get_item(pamh, PAM_USER, &item);
			if (pam_err == PAM_SUCCESS) {
				tmpl_user = (const char *)item;
				if (strcmp(username, tmpl_user) != 0)
					pwd = getpwnam(tmpl_user);
			} else {
				pam_syslog("pam_get_item(PAM_USER)");
			}
			rval = 0;
			break;

		case PAM_AUTH_ERR:
		case PAM_USER_UNKNOWN:
		case PAM_MAXTRIES:
			rval = 1;
			break;

		default:
			pam_syslog("pam_authenticate()");
			rval = -1;
			break;
		}
	}

	if (rval == 0) {
		pam_err = pam_acct_mgmt(pamh, pam_silent);
		switch (pam_err) {
		case PAM_SUCCESS:
			break;
		case PAM_NEW_AUTHTOK_REQD:
			if (skip_auth == 0)
			{
				pam_err = pam_chauthtok(pamh,
				    pam_silent|PAM_CHANGE_EXPIRED_AUTHTOK);
				if (pam_err != PAM_SUCCESS) {
					pam_syslog("pam_chauthtok()");
					rval = 1;
				}
			}
			else
			{
				pam_syslog("pam_acct_mgmt()");
			}
			break;
		default:
			pam_syslog("pam_acct_mgmt()");
			rval = 1;
			break;
		}
	}

	if (rval != 0) {
		pam_end(pamh, pam_err);
		pamh = NULL;
	}
	return (rval);
}

/*
 * Export any environment variables PAM modules may have set
 */
static void
export_pam_environment()
{
	char **pam_env;
	char **pp;

	pam_env = pam_getenvlist(pamh);
	if (pam_env != NULL) {
		for (pp = pam_env; *pp != NULL; pp++) {
			(void)export(*pp);
			free(*pp);
		}
	}
}

/*
 * Perform sanity checks on an environment variable:
 * - Make sure there is an '=' in the string.
 * - Make sure the string doesn't run on too long.
 * - Do not export certain variables.  This list was taken from the
 *   Solaris pam_putenv(3) man page.
 * Then export it.
 */
static int
export(const char *s)
{
	static const char *noexport[] = {
		"SHELL", "HOME", "LOGNAME", "MAIL", "CDPATH",
		"IFS", "PATH", NULL
	};
	char *p;
	const char **pp;
	size_t n;

	if (strlen(s) > 1024 || (p = strchr(s, '=')) == NULL)
		return (0);
	if (strncmp(s, "LD_", 3) == 0)
		return (0);
	for (pp = noexport; *pp != NULL; pp++) {
		n = strlen(*pp);
		if (s[n] == '=' && strncmp(s, *pp, n) == 0)
			return (0);
	}
	*p = '\0';
	(void)setenv(s, p + 1, 1);
	*p = '=';
	return (1);
}
#endif /* USE_PAM */

static void
usage()
{
#ifdef __APPLE__
	(void)fprintf(stderr, "usage: login [-pq] [-h hostname] [username]\n");
	(void)fprintf(stderr, "       login -f [-lpq] [-h hostname] [username [prog [arg ...]]]\n");
#else
	(void)fprintf(stderr, "usage: login [-fp] [-h hostname] [username]\n");
#endif
	exit(1);
}

/*
 * Prompt user and read login name from stdin.
 */
static char *
getloginname()
{
	char *nbuf, *p;
	int ch;

	nbuf = malloc(MAXLOGNAME);
	if (nbuf == NULL)
		err(1, "malloc()");
	do {
		(void)printf("%s", prompt);
		for (p = nbuf; (ch = getchar()) != '\n'; ) {
			if (ch == EOF) {
				badlogin(username);
				bail(NO_SLEEP_EXIT, 0);
			}
			if (p < nbuf + MAXLOGNAME - 1)
				*p++ = ch;
		}
	} while (p == nbuf);

	*p = '\0';
	if (nbuf[0] == '-') {
#ifdef USE_PAM
		pam_silent = 0;
#endif /* USE_PAM */
		memmove(nbuf, nbuf + 1, strlen(nbuf));
	} else {
#ifdef USE_PAM
		pam_silent = PAM_SILENT;
#endif /* USE_PAM */
	}
	return nbuf;
}

#ifdef __APPLE__
#ifndef USE_PAM
static int
rootterm(const char* ttyn)
{
	struct ttyent *t;
	return ((t = getttynam(ttyn)) && t->ty_status & TTY_SECURE);
}
#endif /* !USE_PAM */
#endif /* __APPLE__ */

/*
 * SIGINT handler for motd().
 */
static volatile int motdinterrupt;
static void
sigint(int signo __unused)
{
	motdinterrupt = 1;
}

/*
 * Display the contents of a file (such as /etc/motd).
 */
static int
motd(const char *motdfile)
{
	sig_t oldint;
	FILE *f;
	int ch;

	if ((f = fopen(motdfile, "r")) == NULL)
		return (-1);
	motdinterrupt = 0;
	oldint = signal(SIGINT, sigint);
	while ((ch = fgetc(f)) != EOF && !motdinterrupt)
		putchar(ch);
	signal(SIGINT, oldint);
	if (ch != EOF || ferror(f)) {
		fclose(f);
		return (-1);
	}
	fclose(f);
	return (0);
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

/*
 * SIGALRM handler, to enforce login prompt timeout.
 *
 * XXX This can potentially confuse the hell out of PAM.  We should
 * XXX instead implement a conversation function that returns
 * XXX PAM_CONV_ERR when interrupted by a signal, and have the signal
 * XXX handler just set a flag.
 */
static void
timedout(int signo __unused)
{

	longjmp(timeout_buf, signo);
}

#ifdef __APPLE__
#ifndef USE_PAM
void
checknologin()
{
	int fd, nchars;
	char tbuf[8192];

	if ((fd = open(_PATH_NOLOGIN, O_RDONLY, 0)) >= 0) {
		while ((nchars = read(fd, tbuf, sizeof(tbuf))) > 0)
			(void)write(fileno(stdout), tbuf, nchars);
#ifdef USE_BSM_AUDIT
		au_login_fail("No login", 0);
#endif
		sleep(5);
		exit(0);
	}
}
#endif /* !USE_PAM */

void
dolastlog(quiet)
	int quiet;
{
#ifdef USE_PAM
	if (quiet)
		return;
	if (*lastlog.ll_line) {
		(void)printf("Last login: %.*s ",
		    24-5, (char *)ctime(&lastlog.ll_tv.tv_sec));
		if (*lastlog.ll_host != '\0')
			(void)printf("from %.*s\n",
			    (int)sizeof(lastlog.ll_host),
			    lastlog.ll_host);
		else
			(void)printf("on %.*s\n",
			    (int)sizeof(lastlog.ll_line),
			    lastlog.ll_line);
	}
#else /* !USE_PAM */
	struct lastlogx ll;

	if(!quiet && getlastlogx(pwd->pw_uid, &ll) != NULL) {
		(void)printf("Last login: %.*s ",
				24-5, (char *)ctime(&ll.ll_tv.tv_sec));
		if (*ll.ll_host != '\0')
			(void)printf("from %.*s\n",
					(int)sizeof(ll.ll_host),
					ll.ll_host);
		else
			(void)printf("on %.*s\n",
					(int)sizeof(ll.ll_line),
					ll.ll_line);
	}
#endif /* USE_PAM */
}
#endif /* __APPLE__ */

static void
badlogin(char *name)
{

	if (failures == 0)
		return;
	if (hflag) {
		syslog(LOG_NOTICE, "%d LOGIN FAILURE%s FROM %s",
		    failures, failures > 1 ? "S" : "", hostname);
		syslog(LOG_AUTHPRIV|LOG_NOTICE,
		    "%d LOGIN FAILURE%s FROM %s, %s",
		    failures, failures > 1 ? "S" : "", hostname, name);
	} else {
		syslog(LOG_NOTICE, "%d LOGIN FAILURE%s ON %s",
		    failures, failures > 1 ? "S" : "", tty);
		syslog(LOG_AUTHPRIV|LOG_NOTICE,
		    "%d LOGIN FAILURE%s ON %s, %s",
		    failures, failures > 1 ? "S" : "", tty, name);
	}
	failures = 0;
}

const char *
stypeof(char *ttyid)
{
	struct ttyent *t;

	if (ttyid != NULL && *ttyid != '\0') {
		t = getttynam(ttyid);
		if (t != NULL && t->ty_type != NULL)
			return (t->ty_type);
	}
	return (NULL);
}

static void
refused(const char *msg, const char *rtype, int lout)
{

	if (msg != NULL)
	    printf("%s.\n", msg);
	if (hflag)
		syslog(LOG_NOTICE, "LOGIN %s REFUSED (%s) FROM %s ON TTY %s",
		    pwd->pw_name, rtype, hostname, tty);
	else
		syslog(LOG_NOTICE, "LOGIN %s REFUSED (%s) ON TTY %s",
		    pwd->pw_name, rtype, tty);
	if (lout)
		bail(SLEEP_EXIT, 1);
}

#ifdef USE_PAM
/*
 * Log a PAM error
 */
static void
pam_syslog(const char *msg)
{
	syslog(LOG_ERR, "%s: %s", msg, pam_strerror(pamh, pam_err));
}

/*
 * Shut down PAM
 */
static void
pam_cleanup()
{

	if (pamh != NULL) {
		if (pam_session_established) {
			pam_err = pam_close_session(pamh, 0);
			if (pam_err != PAM_SUCCESS)
				pam_syslog("pam_close_session()");
		}
		pam_session_established = 0;
		if (pam_cred_established) {
			pam_err = pam_setcred(pamh, pam_silent|PAM_DELETE_CRED);
			if (pam_err != PAM_SUCCESS)
				pam_syslog("pam_setcred()");
		}
		pam_cred_established = 0;
		pam_end(pamh, pam_err);
		pamh = NULL;
	}
}
#endif /* USE_PAM */

/*
 * Exit, optionally after sleeping a few seconds
 */
void
bail(int sec, int eval)
{

#ifdef USE_PAM
	pam_cleanup();
#endif /* USE_PAM */
#ifdef USE_BSM_AUDIT
	if (pwd != NULL)
		audit_logout();
#endif
	(void)sleep(sec);
	exit(eval);
}
