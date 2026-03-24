#!/bin/bash
set -e

# Build English version
echo "Building English..."
mdbook build

# Build Japanese version by temporarily swapping book.toml
echo "Building Japanese..."
cp book.toml book-en.toml.bak
cp book-ja.toml book.toml
mdbook build
cp book-en.toml.bak book.toml
rm book-en.toml.bak

# Create a root index.html that redirects to /en/
cat > book/index.html << 'HTML'
<!DOCTYPE html>
<html>
<head>
  <meta http-equiv="refresh" content="0; url=en/">
  <title>Redirecting...</title>
</head>
<body>
  <a href="en/">Promovolve Book (English)</a> |
  <a href="ja/">Promovolve Book (日本語)</a>
</body>
</html>
HTML

echo "Done. Output in book/en/ and book/ja/"
