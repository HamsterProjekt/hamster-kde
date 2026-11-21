#!/bin/sh
# Hamster's MCP server for AI assistants, in the Flatpak. The assistants
# start it as `flatpak run --command=hamster-mcp io.github.HamsterProjekt.HamsterKDE`,
# which the tracking settings write into their configuration.
exec python3 /app/lib/hamster/hamster-mcp.py "$@"
