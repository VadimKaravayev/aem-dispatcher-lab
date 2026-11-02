# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

A standalone lab for an AEM as a Cloud Service (AEMaaCS) Dispatcher configuration. `src/` is the dispatcher config in the standard Cloud Manager layout; it runs locally in the Adobe SDK Docker image in front of a publish instance on the host. There is no application code and no build step: the "build" is validation.

## Prerequisites (not in git)

- `sdk/` is gitignored. It must contain the extracted AEMaaCS SDK Dispatcher Tools (the self-extracting `aem-sdk-dispatcher-tools-*-unix.sh` from the SDK zip). Every script in `scripts/` delegates to `sdk/bin/`. If `sdk/bin` is missing, nothing works.
- Docker must be running. The validator binary (`sdk/bin/validator-darwin-arm64`) is the only phase that does not need it.
- A local AEM publish listening on port 4503 on the host for `scripts/run.sh`.
- `cache/` is gitignored; it is the bind-mounted docroot (`/mnt/var/www`) where the container writes cached files. Inspect it to see what got cached; delete it to flush.

## Commands

All scripts `cd` to the repo root themselves, so they can be run from anywhere.

```bash
scripts/validate.sh     # full Cloud Manager-equivalent check: validator (phase 1) + httpd -t in Docker (phase 2) + immutable-file check (phase 3)
scripts/test.sh         # httpd -t only, prints the fully resolved dispatcher.any (fast syntax check)
scripts/run.sh          # hot-reload container on http://localhost:8080 -> host.docker.internal:4503; edits under src/ reload live
```

Useful variants:

```bash
REWRITE_LOG_LEVEL=trace2 scripts/run.sh          # see how RewriteRules are applied
DISP_LOG_LEVEL=debug scripts/run.sh              # see dispatcher filter/cache decisions
DISP_RUN_MODE=stage scripts/run.sh               # simulate ENVIRONMENT_STAGE (dev is default; prod also valid)
IMMUTABLE_FILES_UPDATE=false scripts/validate.sh # don't prompt to overwrite immutable files in phase 3
sdk/bin/validator full -relaxed src              # validator alone, no Docker
sdk/bin/docker_immutability_check.sh src extract # restore Adobe's immutable files from the image
```

Run `scripts/validate.sh` before considering a config change done. It is the same check Cloud Manager's build step runs, and the validator catches things `httpd -t` does not (filter syntax, forbidden directives).

## Config architecture

`src/opt-in/USE_SOURCES_DIRECTLY` puts the SDK in **flexible mode**: the whole `src/` folder is bind-mounted into the container as-is, so include chains and symlinks must be valid on their own.

Two parallel include trees, one for Apache and one for the dispatcher module:

```
conf.d/dispatcher_vhost.conf        (immutable, Adobe)
  -> conf.d/variables/global.vars
  -> conf.d/enabled_vhosts/*.vhost  (symlink -> available_vhosts/default.vhost)
       -> conf.d/variables/custom.vars
       -> conf.d/rewrites/rewrite.rules -> default_rewrite.rules

conf.dispatcher.d/dispatcher.any    (immutable, Adobe)
  -> conf.dispatcher.d/enabled_farms/*.farm  (symlink -> available_farms/default.farm)
       -> clientheaders/clientheaders.any -> default_clientheaders.any
       -> virtualhosts/virtualhosts.any   -> default_virtualhosts.any
       -> renders/default_renders.any     (${AEM_HOST}:${AEM_PORT}, injected by the SDK script)
       -> filters/filters.any             -> default_filters.any
       -> cache/rules.any                 -> default_rules.any
       -> cache/default_invalidate.any
```

Rules that follow from this:

- **Edit only the non-`default_` files** (`rewrite.rules`, `custom.vars`, `global.vars`, `filters.any`, `rules.any`, `virtualhosts.any`, `clientheaders.any`) and your own `*.vhost` / `*.farm` copies. `default_*` files, `dispatcher_vhost.conf`, `dispatcher.any` and `default.farm` are Adobe-owned; phase 3 of validation fails if they differ from the image. Changes to them have no effect in Cloud Manager.
- **Enable by symlink.** `enabled_vhosts/` and `enabled_farms/` contain relative symlinks into `available_*`. To customize the vhost or farm, copy the default into `available_*` under a new name and repoint the symlink. Git tracks the symlinks; do not replace them with file copies.
- **Variables flow one way.** `custom.vars` is included inside the vhost, so its `Define`s are usable in `rewrite.rules` and the vhost but not in `dispatcher_vhost.conf`. `global.vars` is included before the vhosts.
- **Filter/cache files are `.any` glob rule lists.** Later rules win; the custom `filters.any` appends numbered rules (`/0101`, `/0102`) after the defaults, and new rules should continue that numbering above the default range.

## Current customizations (the diff from the SDK defaults)

- `custom.vars` defines `CONTENT_FOLDER_NAME` (the site root under `/content`).
- `rewrite.rules` redirects `/` to the site's English language master and maps short URLs (`/foo.html`, images) to `/content/${CONTENT_FOLDER_NAME}/...` unless the path starts with a known AEM root (`/apps`, `/bin`, `/content`, `/etc`, `/libs`, ...).
- `filters.any` additionally allows `.model.json` under `/content` and `manifest.webmanifest`.

Compare against `sdk/src/` with `diff -rq sdk/src src` to see the full delta; that is the fastest way to understand what this lab changes.

## Debugging through the chain

When a request to `localhost:8080` misbehaves, read the status before the config:

- 404 that AEM itself returns means the chain works; the content is simply missing on publish.
- 403 is a dispatcher filter (`DISP_LOG_LEVEL=debug` shows which rule) or a rewrite that landed on a denied path.
- 502/503 means the backend is unreachable (publish not running, or wrong host:port).
- `scripts/test.sh` output is the resolved `dispatcher.any`; use it to confirm an `$include` actually pulled in your rule.

## Reference material

Dispatcher background notes live in the shared AEM knowledgebase under `dispatcher-url-delivery/` (see its `INDEX.md`), in particular the note on running the SDK dispatcher in Docker from a lab repo, and the notes on caching/invalidation, cacheability rules, filters and the security checklist. Check there before designing a change.
