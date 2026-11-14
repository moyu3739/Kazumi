# Kazumi Windows vendor copy

This directory is based on `media_kit_video` 1.2.5 resolved from the local
`PUB_CACHE` at the time this Kazumi patch was prepared. The resolved local copy
already included Kazumi-specific Windows adapter, mpv dynamic-binding, and
resource-lifetime edits; this is not represented as an unmodified upstream
release. Review `git diff` in this directory for the four-slot fenced mailbox,
coalesced render notifications, output statistics, and temporary-recovery
support added for the danmaku plus super-resolution freeze.

Upstream package license and notice remain in `LICENSE` and `README.md`.
