#!/bin/sh
set -eu
# Fail early if an old generated project or an invalid launch-screen reference returns.
python3 "${CI_PRIMARY_REPOSITORY_PATH:?}/ios/Tests/check-release-metadata.py"
