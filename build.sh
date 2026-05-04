#!/bin/bash
set -e

# Single-language build (English). The Japanese version was dropped —
# if it returns, this script will need to swap book.toml ↔ book-ja.toml
# and run mdbook twice, mirroring the older two-language flow.
echo "Building English..."
mdbook build

# Root redirect to /en/ — GitHub Pages serves /book/ as the artifact.
cat > book/index.html << 'HTML'
<!DOCTYPE html>
<html>
<head>
  <meta http-equiv="refresh" content="0; url=en/">
  <title>Redirecting...</title>
</head>
<body>
  <a href="en/">Promovolve Book</a>
</body>
</html>
HTML

echo "Done. Output in book/en/"
