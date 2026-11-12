#!/bin/sh
# The Hamster service (io.github.HamsterProjekt.Hamster) with the Markdown storage, in the Flatpak.
HAMSTER_STORAGE=markdown
export HAMSTER_STORAGE
exec python3 /app/lib/hamster/hamster-service.py "$@"
