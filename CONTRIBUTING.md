# Contributing

## Setup

- Linux or macOS with Swift 6.2+ for the core: `swift test`, `just render`.
- macOS with Xcode 27 and `brew install xcodegen just` for the app: `just ios-sim`.
- `just hooks` once, so commits run the core tests.

## Workflow

1. Branch from `main`.
2. Keep PRs focused; title them as Conventional Commits (`feat(fog): sonar pings`,
   `fix(sim): ghost balls tunnel walls`). The title becomes the squash commit.
3. CI must be green: Linux core tests, macOS core tests, simulator + device builds, and
   iPhone Duo screenshots (attached to the run as the `duo-screenshots` artifact).
4. Squash-merge. `main` ships to TestFlight automatically.

## Security

This repo is public. Workflows that touch secrets run only on `main`, only for the owner,
and only through the `testflight` environment. Fork PRs need approval before any workflow
runs, and the macOS job skips forks entirely. Don't add `pull_request_target`, don't echo
environment variables, and don't add self-hosted runners.
