#!/bin/bash
set -euo pipefail
# The dedicated workflow is provisioned disabled. A subsequent verified release
# commit supplies the exact isolated HTTPS origin and prepares the MAS app.
echo "Synca Electron TestFlight: verified remote email origin not configured; no archive or upload." >&2
exit 78
