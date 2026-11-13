/*
 * Copyright (C) the libgit2 contributors. All rights reserved.
 *
 * This file is part of libgit2, distributed under the GNU GPL v2 with
 * a Linking Exception. For full terms see the included COPYING file.
 */
#ifndef INCLUDE_git_version_h__
#define INCLUDE_git_version_h__

#include "common.h"

/**
 * @file git2/version.h
 * @brief The version of libgit2
 * @ingroup Git
 * @{
 */
GIT_BEGIN_DECL

/**
 * The version string for libgit2.  This string follows semantic
 * versioning (v2) guidelines.
 */
#define LIBGIT2_VERSION           "1.9.7"

/** The major version number for this version of libgit2. */
#define LIBGIT2_VERSION_MAJOR      1

/** The minor version number for this version of libgit2. */
#define LIBGIT2_VERSION_MINOR      9

/** The revision ("teeny") version number for this version of libgit2. */
#define LIBGIT2_VERSION_REVISION   7

/** The Windows DLL patch number for this version of libgit2. */
#define LIBGIT2_VERSION_PATCH      0

/**
 * The prerelease string for this version of libgit2.  For development
 * (nightly) builds, this will be "alpha".  For prereleases, this will be
 * a prerelease name like "beta" or "rc1".  For final releases, this will
 * be `NULL`.
 */
#define LIBGIT2_VERSION_PRERELEASE NULL

/**
 * The library ABI soversion for this version of libgit2. This should
 * only be changed when the library has a breaking ABI change, and so
 * may not reflect the library's API version number.
 */
#define LIBGIT2_SOVERSION         "1.9"

/**
 * An integer value representing the libgit2 version number. For example,
 * libgit2 1.6.3 is 1060300.
 */
#define LIBGIT2_VERSION_NUMBER (    \
    (LIBGIT2_VERSION_MAJOR * 1000000) + \
    (LIBGIT2_VERSION_MINOR * 10000) +   \
    (LIBGIT2_VERSION_REVISION * 100))

/**
 * Compare the libgit2 version against a given version. Evaluates to true
 * if the given major, minor, and revision values are greater than or equal
 * to the currently running libgit2 version. For example:
 *
 *  #if LIBGIT2_VERSION_CHECK(1, 6, 3)
 *  # error libgit2 version is >= 1.6.3
 *  #endif
 */
#define LIBGIT2_VERSION_CHECK(major, minor, revision) \
	(LIBGIT2_VERSION_NUMBER >= ((major)*1000000)+((minor)*10000)+((revision)*100))

/** @} */
GIT_END_DECL

#endif
