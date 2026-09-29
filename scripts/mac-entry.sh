#!/bin/bash
# Run from a completely extracted release, including paths with spaces.
set -u
cd "$(dirname "$0")/.." || exit 1
badge_node=""
for badge_candidate in "${CODEX_BADGE_NODE:-}" \
  "${CODEX_BADGE_APP:-/Applications/Codex.app}/Contents/Resources/cua_node/bin/node" \
  "/Applications/ChatGPT.app/Contents/Resources/cua_node/bin/node" \
  "$HOME/Applications/Codex.app/Contents/Resources/cua_node/bin/node" \
  "$HOME/Applications/ChatGPT.app/Contents/Resources/cua_node/bin/node" \
  "$(command -v node 2>/dev/null || true)";
do
  if [ -x "$badge_candidate" ] && "$badge_candidate" -e 'if(+process.versions.node.split(".")[0]<24)process.exit(1);require("node:sqlite")' >/dev/null 2>&1; then
    badge_node="$badge_candidate"
    break
  fi
done
if [ -z "$badge_node" ]; then
  echo "Node.js 24+ was not found. Open the desktop app once or install Node.js 24 LTS, then try again."
  badge_result=1
else
  "$badge_node" ./manage.cjs "$1"
  badge_result=$?
fi
echo
read -r -p "Press Enter to close…" _ || true
exit "$badge_result"
