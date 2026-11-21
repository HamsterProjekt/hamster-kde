# SPDX-License-Identifier: GPL-3.0-or-later
# Shortcuts for building, installing and testing hamster-kde. Each target
# runs one of the scripts (install.sh, scripts/, flatpak/build.sh, tests/),
# which stay the reference; `make help` lists them.
#
# Variables (give them on the command line, e.g. make install HAMSTER=~/src/hamster):
#   HAMSTER  the Hamster checkout the service runs from (default: ../hamster)
#   OUT      where the tests put their screenshots and logs
#            (default: /tmp/hamster-kde-tests)

HAMSTER ?= ../hamster
OUT ?= /tmp/hamster-kde-tests
FLATPAK_ID = io.github.HamsterProjekt.HamsterKDE

.PHONY: help \
	install install-markdown install-sqlite install-backend install-widget uninstall \
	flatpak flatpak-local flatpak-bundle flatpak-widget flatpak-uninstall plasmoid \
	test test-mock test-app test-all test-flatpak-layout \
	sign

help:
	@echo "From the source checkouts, for your user (no root):"
	@echo "  make install           widget + Hamster service from HAMSTER; keeps the current storage"
	@echo "                         (Markdown on a first installation)"
	@echo "  make install-markdown  the same, storing the facts in Markdown files"
	@echo "  make install-sqlite    the same, storing the facts in Hamster's SQLite database"
	@echo "  make install-backend   only the Hamster service and the windows, no widget"
	@echo "  make install-widget    only the Plasma widget (install or upgrade)"
	@echo "  make uninstall         remove all of the above (your data is kept)"
	@echo
	@echo "Flatpak ($(FLATPAK_ID)), needs flatpak-builder:"
	@echo "  make flatpak           build and install, with Hamster from GitHub (main)"
	@echo "  make flatpak-local     build and install, with Hamster from HAMSTER"
	@echo "  make flatpak-bundle    build, install and write hamster-kde.flatpak"
	@echo "  make flatpak-widget    the Plasma widget, started from the Flatpak"
	@echo "  make flatpak-uninstall remove the widget's link to the Flatpak, and the Flatpak"
	@echo "                         (its data in ~/.var/app is kept)"
	@echo
	@echo "Packaging:"
	@echo "  make plasmoid          write hamster-kde.plasmoid, the widget as one file"
	@echo
	@echo "Tests (headless, on private session buses; nothing of yours is touched):"
	@echo "  make test              unit tests (Python, and lib.js if node is there)"
	@echo "  make test-mock         the widget against a mock service (needs PyQt6, dbus-python)"
	@echo "  make test-app          the windows, storage, sync and export against HAMSTER"
	@echo "  make test-flatpak-layout  the install steps of the Flatpak manifest, without building"
	@echo "  make test-all          all of the above; screenshots and logs in OUT"
	@echo
	@echo "Maintainers:"
	@echo "  make sign PR=NUMBER    take authorship of a pull request's commits and"
	@echo "                         sign them off, so that its DCO check passes"

# --- from the source checkouts ---

install:
	./install.sh "$(HAMSTER)"

install-markdown:
	./install.sh --markdown "$(HAMSTER)"

install-sqlite:
	./install.sh --sqlite "$(HAMSTER)"

install-backend:
	scripts/install-backend.sh "$(HAMSTER)"

install-widget:
	kpackagetool6 --type Plasma/Applet --upgrade plasmoid 2>/dev/null \
		|| kpackagetool6 --type Plasma/Applet --install plasmoid

uninstall:
	./install.sh --uninstall

# --- Flatpak ---

flatpak:
	flatpak/build.sh

flatpak-local:
	flatpak/build.sh "$(HAMSTER)"

flatpak-bundle:
	flatpak/build.sh --bundle

flatpak-widget:
	scripts/install-flatpak-widget.sh

flatpak-uninstall:
	scripts/install-flatpak-widget.sh --uninstall
	flatpak uninstall --user -y $(FLATPAK_ID)

plasmoid:
	scripts/package-plasmoid.sh hamster-kde.plasmoid

# --- tests ---

test:
	@set -e; for test in tests/test_*.py; do echo "== $$test"; python3 "$$test"; done
	@if command -v node > /dev/null; then echo "== tests/lib_test.js"; node tests/lib_test.js; \
		else echo "(node is missing: tests/lib_test.js skipped)"; fi

test-mock:
	@mkdir -p "$(OUT)"
	tests/run_backend_test.sh
	tests/run_view_test.sh "$(OUT)/view.png"

test-app:
	tests/run_app_test.sh "$(HAMSTER)" "$(OUT)/app"
	tests/run_storage_test.sh "$(HAMSTER)" "$(OUT)/storage"
	tests/run_sync_test.sh "$(HAMSTER)" "$(OUT)/sync"
	tests/run_export_test.sh "$(HAMSTER)" "$(OUT)/export"

test-flatpak-layout:
	tests/run_flatpak_layout_test.sh "$(HAMSTER)" "$(OUT)/flatpak-layout"

test-all: test test-mock test-app test-flatpak-layout

# --- maintainers ---

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
