#!/bin/sh
set -e
API_BASE="${API_BASE_URL:-}"
cat > /usr/share/nginx/html/config.js <<EOF
window.__IDEA_BOARD_CONFIG__ = {
  apiBaseUrl: "${API_BASE}",
};
EOF
exec nginx -g "daemon off;"
