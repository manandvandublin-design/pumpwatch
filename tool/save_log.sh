#!/usr/bin/env bash
# Saves a failed build log to the ci-logs branch so it can be read with git.
set -e
cp "$1" "$RUNNER_TEMP/build.log"
git config user.name ci && git config user.email ci@users.noreply.github.com
git checkout --orphan ci-logs >/dev/null 2>&1
git rm -rfq . >/dev/null 2>&1 || true
cp "$RUNNER_TEMP/build.log" build.log
git add build.log && git commit -qm "build log" && git push -qf origin ci-logs
