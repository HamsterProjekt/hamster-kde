#!/bin/sh
# The Hamster service (org.gnome.Hamster) with the Markdown storage, in the Flatpak.
HAMSTER_STORAGE=markdown
export HAMSTER_STORAGE
exec python3 /app/lib/hamster/hamster-service.py "$@"
