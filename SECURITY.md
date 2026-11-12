# Security policy

## Reporting a vulnerability

Please don't report security problems in public issues or discussions.

Report them privately instead: open the repository's
[Security tab](https://github.com/HamsterProjekt/hamster-kde/security) and
choose **Report a vulnerability**. Only the maintainers can see the report,
and we can work on a fix and an advisory together there.

Please include:

- what the problem is, and what an attacker could do with it
- the steps to reproduce it, or a proof of concept
- the version (the Flatpak release, or the commit) and how you installed it

We will reply within a week, and keep you informed until it is fixed. Unless
you prefer otherwise, we credit you in the advisory.

## Supported versions

Only the latest [release](https://github.com/HamsterProjekt/hamster-kde/releases)
and the `main` branch get security fixes.

## Scope

This policy covers the code in this repository, for example:

- the Plasma panel widget
- the Qt Quick windows, and the reports they export
- `install.sh`, the scripts, the Flatpak and the GitHub Actions workflows

Report problems in other projects to them:

- [hamster](https://github.com/HamsterProjekt/hamster), for the Hamster
  service, its D-Bus interface and the Markdown backend
- the libraries that hamster-kde uses, such as Qt, Kirigami and KDE Plasma
