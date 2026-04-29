# Canopy — Makefile (passthrough to just)
#
# This project uses 'just' as its command runner.
# Install: brew install just
# Usage:   just --list
#
# This Makefile delegates all targets to just for backwards compatibility.
# If you don't have just installed, run: brew install just

%:
	@just $@ 2>/dev/null || (echo "Error: 'just' is not installed. Run: brew install just" && exit 1)

.DEFAULT_GOAL := help

help:
	@just --list 2>/dev/null || echo "Install 'just' first: brew install just"
