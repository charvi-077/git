#!/bin/sh

test_description='git rebase interactive amend'

. ./test-lib.sh

. "$TEST_DIRECTORY"/lib-rebase.sh

EMPTY=""

# use test_pause for debugging 
# u may use -v or -i or -d option also , 
# where -dv used to run test_debug commands 
# u may also use --run=1-2 , to run particular tests.
#

test_expect_success 'setup' '
	### making a message file and expected message file ###
	cat >message <<-EOF &&                    
		amend! B                  
		${EMPTY}
		new subject
		${EMPTY}
		new
		body
		EOF
	sed "1,2d" message >expected-message &&
	
	### making initial commits A and B with tags on master branch ###
	test_commit A A &&                        
	test_commit B B &&
    
	### saving author details in expected-author file ###
	git cat-file commit HEAD | grep ^author >expected-author &&  
	ORIG_AUTHOR_NAME="$GIT_AUTHOR_NAME" &&
	ORIG_AUTHOR_EMAIL="$GIT_AUTHOR_EMAIL" &&
	
	### changing the author details ###
	GIT_AUTHOR_NAME="Amend Author" &&
	GIT_AUTHOR_EMAIL="amend@example.com" &&

	#### commit again A file with message saved in message file written above with A1 tag ###
	test_commit "$(cat message)" A A1 A1 && 

	### commit again A with A2 and A3 tag and message ###
	test_commit A2 A &&
	test_commit A3 A &&

	### restoring the original author ###
	GIT_AUTHOR_NAME="$ORIG_AUTHOR_NAME" &&
	GIT_AUTHOR_EMAIL="$ORIG_AUTHOR_EMAIL" &&

	### change branch to conflicts from tag A ###
	git checkout -b conflicts-branch A &&
	
	### commit again conflict message and content in A file ###
	test_commit conflicts A &&

	### calling fake editor function as in lib-rebase.sh ###
	set_fake_editor &&

	### switch new branch branch from tag B ###
	git checkout -b branch B &&

	### do changes in B file ###
	echo B1 >B &&

	### increase time ###
	test_tick &&

	### make fixup! commit with current changes for head on tag B ###
	git commit --fixup=HEAD -a &&

	### increase timer ###
	test_tick &&

	### make empty commit with message from std i/p ###
	git commit --allow-empty -F - <<-EOF &&
		amend! B
		${EMPTY}
		B
		${EMPTY}
		edited 1
		EOF

	### increase timer ###
	test_tick &&

	### make empty commit with messafe from std i/p ###
	git commit --allow-empty -F - <<-EOF &&
		amend! amend! B
		${EMPTY}
		B
		${EMPTY}
		edited 1
		${EMPTY}
		edited 2
		EOF
	
	### edit B file ###
	echo B2 >B && 
	test_tick && 

	### make squash! commit with taking changes in B file ##
	FAKE_COMMIT_AMEND="edited squash" git commit --squash=HEAD -a &&

	### edit B file ###
	echo B3 >B &&
	test_tick &&

	### commit current changes with message from std i/p ###
	git commit -a -F - <<-EOF &&
		amend! amend! amend! B
		${EMPTY}
		B
		${EMPTY}
		edited 1
		${EMPTY}
		edited 2
		${EMPTY}
		edited 3
		EOF

    ### changing the author and commiter details ###
	GIT_AUTHOR_NAME="Rebase Author" &&
	GIT_AUTHOR_EMAIL="rebase.author@example.com" &&
	GIT_COMMITTER_NAME="Rebase Committer" &&
	GIT_COMMITTER_EMAIL="rebase.committer@example.com"
'

test_expect_success 'simple amend works' '
	test_when_finished "test_might_fail git rebase --abort" &&
	git checkout --detach A2 &&
	FAKE_LINES="1 amend 2" git rebase -i B &&
	test_cmp_rev HEAD^ B &&
	test_cmp_rev HEAD^{tree} A2^{tree} &&
	test "$(git log -n1 --format=%B HEAD)" = A2
'

test_expect_success 'amend removes amend! from message' '
	test_when_finished "test_might_fail git rebase --abort" &&
	git checkout --detach A1 &&
	FAKE_LINES="1 amend 2" git rebase -i A &&
	test_cmp_rev HEAD^ A &&
	test_cmp_rev HEAD^{tree} A1^{tree} &&
	git cat-file commit HEAD | sed -e 1,/^$/d >actual-message &&
	test_cmp expected-message actual-message &&
	git cat-file commit HEAD | grep ^author >actual-author &&
	test_cmp expected-author actual-author
'

test_expect_success 'amend with conflicts gives correct message' '
	test_when_finished "test_might_fail git rebase --abort" && 
	git checkout --detach A1 &&  
	test_must_fail env FAKE_LINES="1 amend 2" git rebase -i conflicts &&
	git checkout --theirs -- A && 
	git add A &&
	FAKE_COMMIT_AMEND=edited git rebase --continue && 
	test_cmp_rev HEAD^ conflicts && 
	test_cmp_rev HEAD^{tree} A1^{tree} && 
	test_write_lines "" edited >>expected-message && 
	git cat-file commit HEAD | sed -e 1,/^$/d >actual-message && 
	test_cmp expected-message actual-message && 
	git cat-file commit HEAD | grep ^author >actual-author && 
	test_cmp expected-author actual-author 
'

test_expect_success 'skipping amend after fixup gives correct message' '
	test_when_finished "test_might_fail git rebase --abort" && 
	git checkout --detach A3 && 
	test_must_fail env FAKE_LINES="1 fixup 2 amend 4" git rebase -i A && 
	git reset --hard &&
	FAKE_COMMIT_AMEND=edited git rebase --continue && 
	test "$(git log -n1 --format=%B HEAD)" = B 
'

test_expect_success 'sequence of fixup, amend & squash --signoff works' '
	git checkout --detach branch && 
	FAKE_LINES="1 fixup 2 amend 3 amend 4 squash 5 amend 6" \
		FAKE_COMMIT_AMEND=squashed \
		FAKE_MESSAGE_COPY=actual-squash-message \
		git -c commit.status=false rebase -ik --signoff A && 
	git diff-tree --exit-code --patch HEAD branch -- && 
	test_cmp_rev HEAD^ A && 
	test_i18ncmp "$TEST_DIRECTORY/t3437/expected-squash-message" \
		actual-squash-message  
'

test_expect_success 'first amend commented out in sequence fixup amend amend' '
	test_when_finished "test_might_fail git rebase --abort" &&
	git checkout branch && git checkout --detach branch~2 && 
	git log --format=%b -1 >expected-commit-message && 
	FAKE_LINES="1 fixup 2 amend 3 amend 4" git rebase -i A && 
	git log --format=%B -1 >actual-commit-message &&
	test_cmp_rev HEAD^ A &&
	test_cmp expected-commit-message actual-commit-message	
'

test_done