#!/bin/sh
set -eu
# A mounted Railway volume initially belongs to root. The service itself never
# runs as root, and cannot alter installed model/code files.
mkdir -p "${OMR_DATA_DIR:-/data}"
chown stringmap:stringmap "${OMR_DATA_DIR:-/data}"
exec gosu stringmap "$@"
