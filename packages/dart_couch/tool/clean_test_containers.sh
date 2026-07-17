#!/usr/bin/env bash
#
# Removes CouchDB/nginx containers left behind by crashed test runs.
#
# Each container started by the test suite is tagged with the
# `dart_couch_test` label (see test/helper/helper.dart and
# test/helper/couch_test_manager.dart). A normal run removes its own container
# in tearDown; this script is only for cleaning up leftovers after a crash.
#
# It is intentionally NOT run from inside the suite: with parallel suites, a
# global "kill all" would destroy sibling containers that are still in use.
# Run it manually, or as a pre-test step when the machine is otherwise idle.
#
#   ./tool/clean_test_containers.sh
#
set -euo pipefail

label="dart_couch_test"

ids="$(docker ps -aq --filter "label=${label}")"

if [ -z "${ids}" ]; then
  echo "No leftover test containers (label=${label})."
  exit 0
fi

echo "Removing leftover test containers (label=${label}):"
echo "${ids}"
# -f: force-stop if running, -v: also remove anonymous volumes.
echo "${ids}" | xargs docker rm -fv
echo "Done."
