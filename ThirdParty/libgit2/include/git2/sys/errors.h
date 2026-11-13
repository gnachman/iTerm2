/*
 * Copyright (C) the libgit2 contributors. All rights reserved.
 *
 * This file is part of libgit2, distributed under the GNU GPL v2 with
 * a Linking Exception. For full terms see the included COPYING file.
 */

#ifndef INCLUDE_sys_git_errors_h__
#define INCLUDE_sys_git_errors_h__

#include "git2/common.h"

/**
 * @file git2/sys/errors.h
 * @brief Advanced error handling
 * @ingroup Git
 *
 * Error handling for advanced consumers; those who use callbacks
 * or those who create custom databases.
 * @{
 */
GIT_BEGIN_DECL

/**
 * Clear the last library error that occurred for this thread.
 */
GIT_EXTERN(void) git_error_clear(void);

/**
 * Set the error message string for this thread, using `printf`-style
 * formatting.
 *
 * This function is public so that custom ODB backends and the like can
 * relay an error message through libgit2.  Most regular users of libgit2
 * will never need to call this function -- actually, calling it in most
 * circumstances (for example, calling from within a callback function)
 * will just end up having the value overwritten by libgit2 internals.
 *
 * This error message is stored in thread-local storage and only applies
 * to the particular thread that this libgit2 call is made from.
 *
 * @param error_class One of the `git_error_t` enum above describing the
 *                    general subsystem that is responsible for the error.
 * @param fmt The `printf`-style format string; subsequent arguments must
 *            be the arguments for the format string.
 */
GIT_EXTERN(void) git_error_set(int error_class, const char *fmt, ...)
                 GIT_FORMAT_PRINTF(2, 3);

/**
 * Set the error message string for this thread.  This function is like
 * `git_error_set` but takes a static string instead of a `printf`-style
 * format.
 *
 * @param error_class One of the `git_error_t` enum above describing the
 *                    general subsystem that is responsible for the error.
 * @param string The error message to keep
 * @return 0 on success or -1 on failure
 */
GIT_EXTERN(int) git_error_set_str(int error_class, const char *string);

/**
 * Set the error message to a special value for memory allocation failure.
 *
 * The normal `git_error_set_str()` function attempts to `strdup()` the
 * string that is passed in.  This is not a good idea when the error in
 * question is a memory allocation failure.  That circumstance has a
 * special setter function that sets the error string to a known and
 * statically allocated internal value.
 */
GIT_EXTERN(void) git_error_set_oom(void);

/** @} */
GIT_END_DECL

#endif
