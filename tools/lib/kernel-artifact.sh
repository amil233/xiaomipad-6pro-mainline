#!/bin/sh
# SPDX-License-Identifier: MIT
#
# Find the kernel CI artifact to use, without storing its commit anywhere.
#
# A CI artifact is a directory named liuqin-kernel-<commit> whose
# kernel/build-info.json records the same commit.  That agreement, plus the
# SHA256SUMS the callers verify, is the consistency check; nothing in the
# repository pre-records a commit.
#
# Source this file, then call:
#   resolve_kernel_artifact PROJECT_ROOT WORKSPACE_ROOT [ARTIFACT_OR_KERNEL_DIR]
# It sets ARTIFACT, KERNEL_DIR, MODULES_DIR and KERNEL_COMMIT and returns 1 when
# no consistent artifact is available.  The caller prints its own message.

resolve_kernel_artifact() {
	_resolve_project=$1
	_resolve_workspace=$2
	_resolve_requested=${3:-}
	if [ -n "$_resolve_requested" ]; then
		if [ -d "$_resolve_requested/kernel" ] && [ ! -f "$_resolve_requested/build-info.json" ]; then
			ARTIFACT=$(CDPATH= cd -- "$_resolve_requested" && pwd) || return 1
		else
			KERNEL_DIR=$(CDPATH= cd -- "$_resolve_requested" 2>/dev/null && pwd) || return 1
			ARTIFACT=$(dirname "$KERNEL_DIR")
		fi
	else
		ARTIFACT=$(ls -dt "$_resolve_workspace"/ci/liuqin-kernel-* 2>/dev/null | head -n 1)
		[ -n "$ARTIFACT" ] || return 1
		ARTIFACT=$(CDPATH= cd -- "$ARTIFACT" && pwd) || return 1
	fi
	KERNEL_DIR=$ARTIFACT/kernel
	MODULES_DIR=$ARTIFACT/kernel-modules
	[ -f "$KERNEL_DIR/build-info.json" ] || return 1
	KERNEL_COMMIT=$(python3 -c \
		'import json, sys; print(json.load(open(sys.argv[1]))["commit"])' \
		"$KERNEL_DIR/build-info.json" 2>/dev/null) || return 1
	case $KERNEL_COMMIT in
	*[!0-9a-f]*) return 1 ;;
	'') return 1 ;;
	esac
	[ "$(basename "$ARTIFACT")" = "liuqin-kernel-$KERNEL_COMMIT" ] || return 1
	return 0
}
