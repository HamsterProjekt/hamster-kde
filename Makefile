# SPDX-License-Identifier: GPL-3.0-or-later
# Maintainer's helpers; nothing here builds or installs (see install.sh).

.PHONY: help sign

help:
	@echo "make sign PR=NUMBER   take authorship of a pull request's commits and"
	@echo "                      sign them off, so that its DCO check passes"

# Makes you the author of every commit of the pull request, adds your
# "Signed-off-by:" line (and your signature, if git is set to sign), and
# pushes the branch back. For pull requests whose commits were made for you
# under another name, such as Claude's: by signing off, you certify the
# Developer Certificate of Origin for them, so read them first.
# Needs GitHub's gh, and a clean working tree.
sign:
	@test -n "$(PR)" || { echo "usage: make sign PR=NUMBER" >&2; exit 2; }
	@command -v gh >/dev/null || { echo "make sign needs GitHub's gh" >&2; exit 1; }
	@test -z "$$(git status --porcelain --untracked-files=no)" || \
		{ echo "commit or stash your changes first" >&2; exit 1; }
	@set -e; \
	base="$$(gh pr view "$(PR)" --json baseRefName --jq .baseRefName)"; \
	gh pr checkout "$(PR)"; \
	git fetch origin "$$base"; \
	from="$$(git merge-base HEAD FETCH_HEAD)"; \
	echo "Commits of pull request $(PR):"; \
	git log --format='  %h %an: %s' "$$from..HEAD"; \
	git rebase --rebase-merges \
		--exec 'git commit --amend --no-edit --reset-author --signoff' "$$from"; \
	git push --force-with-lease; \
	echo "Signed off as $$(git config user.name) <$$(git config user.email)> and pushed."
