# Changelog

Each entry is an image set this bundle pinned — exactly what `git pull` moves you to.
Components version independently, so an entry lists only what changed.

Pins are bumped automatically as releases land on
[ghcr.io/devopsfromzero](https://github.com/devopsfromzero?tab=packages); see the
`image:` lines in [`docker-compose.yml`](docker-compose.yml) for the current set.

To move to an entry: `git checkout <that commit> && docker compose up -d`.
To roll back: same, with an earlier one.

<!-- new-entries-below -->

## 2026-07-21

- ui `v0.5.6`


## 2026-07-21

- backend `v2.5.8`
- ui `v0.5.5`
- agent `v0.6.4`


## 2026-07-21

- backend `v2.5.7`
- ui `v0.5.4`


## 2026-07-20

- backend `v2.5.6`
- ui `v0.5.3`
- agent `v0.6.3`


## 2026-07-19

- backend `v2.5.2`
- ui `v0.5.2`


## 2026-07-18

- backend `v2.5.1`
- ui `v0.5.1`


## 2026-07-18

- backend `v2.5.0`


## 2026-07-18

- ui `v0.5.0`


## 2026-07-17

- backend `v2.4.3`
- ui `v0.4.3`
- terminal `v1.1.0`
- agent `v0.6.2`
- gateway `v0.1.1`

First pinned bundle. Until now the compose defaulted to `:latest`, so there was no
recorded set to point at — two clones of the same commit could run different stacks,
and rolling back meant guessing which versions had worked together.
