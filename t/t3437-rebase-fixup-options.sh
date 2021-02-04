#!/bin/sh
#
# Copyright (c) 2018 Phillip Wood
#

test_description='git rebase interactive fixup options

This test checks the "fixup [-C|-c]" command of rebase interactive.
In addition to amending the contents of the commit, "fixup -C"
replaces the original commit message with the message of the fixup
commit. "fixup -c" also replaces the original message, but opens the
editor to allow the user to edit the message before committing.
'

. ./test-lib.sh

. "$TEST_DIRECTORY"/lib-rebase.sh

EMPTY=""

# test_commit_message <rev> -m <msg>
# test_commit_message <rev> <path>
# Verify that the commit message of <rev> matches
# <msg> or the content of <path>.
test_commit_message () {
	git show --no-patch --pretty=format:%B "$1" >actual &&
	case "$2" in
	-m) echo "$3" >expect &&
		test_cmp expect actual ;;
	*) test_cmp "$2" actual ;;
	esac
}

test_expect_success 'setup' '
	cat >message <<-EOF &&
	new subject
	$EMPTY
	new
	body
	EOF
	test_commit A A &&
	test_commit B B &&

	set_fake_editor &&
	git checkout -b test-branch &&
	test_commit "$(cat message)" A A1 A1 &&
	test_commit A2 A &&
	test_commit A3 A &&
	git checkout -b conflicts-branch A &&
	test_commit conflicts A
'

test_expect_success 'simple fixup -C works' '
	test_when_finished "test_might_fail git rebase --abort" &&
	git checkout --detach A1 &&
	git log -1 --pretty=format:%B >expected-message &&
	FAKE_LINES="1 fixup-C 2 " git rebase -i A &&
	test_cmp_rev HEAD^ A &&
	test_cmp_rev HEAD^{tree} A1^{tree} &&
	test_commit_message HEAD expected-message
'

test_expect_success 'simple fixup -c works' '
	test_when_finished "test_might_fail git rebase --abort" &&
	git checkout --detach A2 &&
	git log -1 --pretty=format:%B HEAD~ >expected-message &&
	test_write_lines "" "Modified A1" >>expected-message &&
	FAKE_LINES="1 fixup-c 2 3" \
		FAKE_COMMIT_AMEND="Modified A1" \
		git rebase -i A &&
	test_cmp_rev HEAD^{tree} A2^{tree} &&
	test_commit_message HEAD~ expected-message
'

test_expect_success 'fixup -C with conflicts gives correct message' '
	test_when_finished "test_might_fail git rebase --abort" &&
	git checkout --detach A1 &&
	git log -1 --pretty=format:%B HEAD >expected-message &&
	test_write_lines "" "edited" >>expected-message &&
	test_must_fail env FAKE_LINES="1 fixup-C 2" git rebase -i conflicts &&
	git checkout --theirs -- A &&
	git add A &&
	FAKE_COMMIT_AMEND=edited git rebase --continue &&
	test_cmp_rev HEAD^ conflicts &&
	test_cmp_rev HEAD^{tree} A1^{tree} &&
	test_commit_message HEAD expected-message
'

test_expect_success 'skipping fixup -C after fixup gives correct message' '
	test_when_finished "test_might_fail git rebase --abort" &&
	git checkout --detach A3 &&
	test_must_fail env FAKE_LINES="1 fixup 2 fixup-C 4" git rebase -i A &&
	git reset --hard &&
	FAKE_COMMIT_AMEND=edited git rebase --continue &&
	test_commit_message HEAD -m "B"
'

test_expect_success 'first fixup -C commented out in sequence fixup fixup -C fixup -C' '
	test_when_finished "test_might_fail git rebase --abort" &&
	git checkout --detach A3 &&
	git log -1 --pretty=format:%B >expected-message &&
	FAKE_LINES="1 fixup 2 fixup-C 3 fixup-C 4" git rebase -i A &&
	test_cmp_rev HEAD^ A &&
	test_commit_message HEAD expected-message
'

test_expect_success 'multiple fixup -c opens editor once' '
	test_when_finished "test_might_fail git rebase --abort" &&
	git checkout --detach A3 &&
	base=$(git rev-parse HEAD~4) &&
	FAKE_COMMIT_MESSAGE="Modified-A3" \
		FAKE_LINES="1 fixup-C 2 fixup-c 3 fixup-c 4" \
		EXPECT_HEADER_COUNT=4 \
		git rebase -i $base &&
	test_commit_message HEAD -m "Modified-A3" &&
	test_cmp_rev $base HEAD^ &&
	git show > raw &&
	grep Modified-A3 raw >out &&
	test_line_count = 1 out
'

test_expect_success 'sequence squash, fixup & fixup -c gives combined message' '
	test_when_finished "test_might_fail git rebase --abort" &&
	git checkout --detach A3 &&
	FAKE_LINES="1 squash 2 fixup 3 fixup-c 4" \
		FAKE_MESSAGE_COPY=actual-combined-message \
		git -c commit.status=false rebase -i A &&
	test_i18ncmp "$TEST_DIRECTORY/t3437/expected-combined-message" \
		actual-combined-message &&
	test_cmp_rev HEAD^ A
'

test_done
