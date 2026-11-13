/*
 * Copyright (C) the libgit2 contributors. All rights reserved.
 *
 * This file is part of libgit2, distributed under the GNU GPL v2 with
 * a Linking Exception. For full terms see the included COPYING file.
 */
#ifndef INCLUDE_sys_git_commit_h__
#define INCLUDE_sys_git_commit_h__

#include "git2/common.h"
#include "git2/types.h"
#include "git2/oid.h"

/**
 * @file git2/sys/commit.h
 * @brief Low-level Git commit creation
 * @defgroup git_commit Low-level Git commit creation
 * @ingroup Git
 * @{
 */
GIT_BEGIN_DECL

/**
 * Create new commit in the repository from a list of `git_oid` values.
 *
 * See documentation for `git_commit_create()` for information about the
 * parameters, as the meaning is identical excepting that `tree` and
 * `parents` now take `git_oid`.  This is a dangerous API in that nor
 * the `tree`, neither the `parents` list of `git_oid`s are checked for
 * validity.
 *
 * @param id Pointer in which to store the OID of the newly created commit
 *
 * @param repo Repository where to store the commit
 *
 * @param update_ref If not NULL, name of the reference that
 *	will be updated to point to this commit. If the reference
 *	is not direct, it will be resolved to a direct reference.
 *	Use "HEAD" to update the HEAD of the current branch and
 *	make it point to this commit. If the reference doesn't
 *	exist yet, it will be created. If it does exist, the first
 *	parent must be the tip of this branch.
 *
 * @param author Signature with author and author time of commit
 *
 * @param committer Signature with committer and * commit time of commit
 *
 * @param message_encoding The encoding for the message in the
 *  commit, represented with a standard encoding name.
 *  E.g. "UTF-8". If NULL, no encoding header is written and
 *  UTF-8 is assumed.
 *
 * @param message Full message for this commit
 *
 * @param tree An instance of a `git_tree` object that will
 *  be used as the tree for the commit. This tree object must
 *  also be owned by the given `repo`.
 *
 * @param parent_count Number of parents for this commit
 *
 * @param parents Array of `parent_count` pointers to `git_commit`
 *  objects that will be used as the parents for this commit. This
 *  array may be NULL if `parent_count` is 0 (root commit). All the
 *  given commits must be owned by the `repo`.
 *
 * @return 0 or an error code
 *	The created commit will be written to the Object Database and
 *	the given reference will be updated to point to it
 */
GIT_EXTERN(int) git_commit_create_from_ids(
	git_oid *id,
	git_repository *repo,
	const char *update_ref,
	const git_signature *author,
	const git_signature *committer,
	const char *message_encoding,
	const char *message,
	const git_oid *tree,
	size_t parent_count,
	const git_oid *parents[]);

/**
 * Callback function to return parents for commit.
 *
 * This is invoked with the count of the number of parents processed so far
 * along with the user supplied payload.  This should return a git_oid of
 * the next parent or NULL if all parents have been provided.
 *
 * @param idx the index of the parent
 * @param payload the user-specified payload
 * @return the object id of the parent, or NULL if there are no further parents
 */
typedef const git_oid * GIT_CALLBACK(git_commit_parent_callback)(size_t idx, void *payload);

/**
 * Create a new commit in the repository with an callback to supply parents.
 *
 * See documentation for `git_commit_create()` for information about the
 * parameters, as the meaning is identical excepting that `tree` takes a
 * `git_oid` and doesn't check for validity, and `parent_cb` is invoked
 * with `parent_payload` and should return `git_oid` values or NULL to
 * indicate that all parents are accounted for.
 *
 * @param id Pointer in which to store the OID of the newly created commit
 *
 * @param repo Repository where to store the commit
 *
 * @param update_ref If not NULL, name of the reference that
 *	will be updated to point to this commit. If the reference
 *	is not direct, it will be resolved to a direct reference.
 *	Use "HEAD" to update the HEAD of the current branch and
 *	make it point to this commit. If the reference doesn't
 *	exist yet, it will be created. If it does exist, the first
 *	parent must be the tip of this branch.
 *
 * @param author Signature with author and author time of commit
 *
 * @param committer Signature with committer and * commit time of commit
 *
 * @param message_encoding The encoding for the message in the
 *  commit, represented with a standard encoding name.
 *  E.g. "UTF-8". If NULL, no encoding header is written and
 *  UTF-8 is assumed.
 *
 * @param message Full message for this commit
 *
 * @param tree An instance of a `git_tree` object that will
 *  be used as the tree for the commit. This tree object must
 *  also be owned by the given `repo`.
 *
 * @param parent_cb Callback to invoke to obtain parent information
 *
 * @param parent_payload User-specified payload to provide to the callback
 *
 * @return 0 or an error code
 *	The created commit will be written to the Object Database and
 *	the given reference will be updated to point to it
 */
GIT_EXTERN(int) git_commit_create_from_callback(
	git_oid *id,
	git_repository *repo,
	const char *update_ref,
	const git_signature *author,
	const git_signature *committer,
	const char *message_encoding,
	const char *message,
	const git_oid *tree,
	git_commit_parent_callback parent_cb,
	void *parent_payload);

/** @} */
GIT_END_DECL

#endif
