#!/bin/bash
set -e

# Two-language build: mdbook has no native multi-lang support, so the
# Japanese pass temporarily swaps book.toml for book-ja.toml (src-ja/,
# build-dir book/ja). The lang-toggle.{js,css} assets add an EN/JA
# switch to the menu bar of both builds.
echo "Building English..."
mdbook build

echo "Building Japanese..."
cp book.toml book-en.toml.bak
cp book-ja.toml book.toml
mdbook build
cp book-en.toml.bak book.toml
rm book-en.toml.bak

# Root redirect to /en/ — GitHub Pages serves /book/ as the artifact.
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
