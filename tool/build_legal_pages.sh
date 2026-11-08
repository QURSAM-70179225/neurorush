#!/usr/bin/env bash
# Builds public/privacy.html and public/delete-account.html for Firebase
# Hosting (Google Play requires both URLs). Usage:
#   tool/build_legal_pages.sh support@yourdomain.com
set -euo pipefail
email="${1:-}"
if [[ ! "$email" =~ ^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$ ]]; then
  echo "Usage: $0 support@yourdomain.com" >&2
  exit 1
fi
cd "$(dirname "$0")/.."
mkdir -p public
for page in privacy delete-account; do
  sed "s/{{SUPPORT_EMAIL}}/${email//\//\\/}/g" "legal/$page.template.html" > "public/$page.html"
done
echo "Wrote public/privacy.html and public/delete-account.html"
