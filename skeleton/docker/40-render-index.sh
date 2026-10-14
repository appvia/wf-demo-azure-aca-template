#!/bin/sh
# Writes the page from GREETING (baked into the image) and APP_RELEASE (set by
# the deployment), at container start. Run by the nginx image's entrypoint.
set -eu

escape() {
  printf '%s' "$1" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'
}

greeting="$(escape "${GREETING:-Hello}")"
release="$(escape "${APP_RELEASE:-unknown}")"

cat > /usr/share/nginx/html/index.html <<EOF
<!doctype html>
<html lang="en">
<head><meta charset="utf-8"><title>${greeting}</title></head>
<body>
<h1>${greeting}</h1>
<p>release ${release}</p>
</body>
</html>
EOF
