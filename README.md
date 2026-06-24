# beacon-agent

**Deploy repo for the Beacon agent.** This repo doesn't hold source — it *publishes*
the agent. The agent is **built** in the monorepo [`allot-rnd/beacon`](https://github.com/allot-rnd/beacon)
and **published** here as the GHCR OCI artifact `ghcr.io/allot-rnd/beacon-agent`.

## Why the split

GHCR records package ownership by **whichever repo's token runs the push**. Publishing
the agent from *this* repo makes the package owned by `allot-rnd/beacon-agent`, so a
fine-grained `read:packages` PAT scoped to **only this repo** pulls **only the agent** —
never the board image (`ghcr.io/allot-rnd/beacon`, which stays owned by the monorepo).

## Flow

```
allot-rnd/beacon (release.yml)            allot-rnd/beacon-agent (publish.yml)
  build 5 binaries + installers   ─┐
  upload to GitHub Release         │  repository_dispatch(publish-agent, tag)
  fire repository_dispatch  ───────┴────────────►  download release binaries
                                                   oras push → ghcr.io/.../beacon-agent
```

## Required secrets

| Repo | Secret | Token (fine-grained) |
|---|---|---|
| `allot-rnd/beacon` | `AGENT_PUBLISH_TOKEN` | `allot-rnd/beacon-agent` → Contents: R/W (fire the dispatch) |
| `allot-rnd/beacon-agent` | `MONOREPO_READ_TOKEN` | `allot-rnd/beacon` → Contents: Read (download the built binaries) |

(One PAT scoped to both repos, stored in both, also works.)

## Manual publish

Actions → **Publish agent OCI artifact** → Run workflow → enter the monorepo release
tag (e.g. `v0.8.4`).
