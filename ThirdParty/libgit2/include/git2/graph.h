/*
 * Copyright (C) the libgit2 contributors. All rights reserved.
 *
 * This file is part of libgit2, distributed under the GNU GPL v2 with
 * a Linking Exception. For full terms see the included COPYING file.
 */
#ifndef INCLUDE_git_graph_h__
#define INCLUDE_git_graph_h__

#include "common.h"
#include "types.h"
#include "oid.h"

/**
 * @file git2/graph.h
 * @brief Git graph traversal routines
 * @defgroup git_revwalk Git graph traversal routines
 * @ingroup Git
 * @{
 */
GIT_BEGIN_DECL

/**
 * Count the number of unique commits between two commit objects
 *
 * There is no need for branches containing the commits to have any
 * upstream relationship, but it helps to think of one as a branch and
 * the other as its upstream, the `ahead` and `behind` values will be
 * what git would report for the branches.
 *
 * @param ahead number of unique from commits in `upstream`
 * @param behind number of unique from commits in `local`
 * @param repo the repository where the commits exist
 * @param local the commit for local
 * @param upstream the commit for upstream
 */
GIT_EXTERN(int) git_graph_ahead_behind(size_t *ahead, size_t *behind, git_repository *repo, const git_oid *local, const git_oid *upstream);


/**
 * Determine if a commit is the descendant of another commit.
 *
 * Note that a commit is not considered a descendant of itself, in contrast
 * to `git merge-base --is-ancestor`.
 *
 * @param commit a previously loaded commit.
 * @param ancestor a potential ancestor commit.
 * @return 1 if the given commit is a descendant of the potential ancestor,
 * 0 if not, error code otherwise.
 */
GIT_EXTERN(int) git_graph_descendant_of(
	git_repository *repo,
	const git_oid *commit,
	const git_oid *ancestor);

/** @} */
GIT_END_DECL
#endif
