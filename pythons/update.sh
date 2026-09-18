#!/usr/bin/env bash
#
# A script to generate md5sum/sha256sum files and index.html
#
# Usage:
#
# 1. Modify `./index.html` and add an entry for archive you want to add.
#    You can omit the sha256sum for the archive this time.
# 2. Download the archive from origin and save it in `./source`
# 3. Run `./update.sh`
# 4. Check diff of `./index.html` if the checksum is calculated properly
# 5. Commit the checksum-named archive files
# 6. Push changes to the origin
#
# To add a prebuilt CPython, copy the archive, metadata and definition produced
# by `pyenv binary package` to `./binaries`. The index entry is generated here.
#

set -e
set -x

compute_sha2() {
  local output
  if type shasum &>/dev/null; then
    output="$(shasum -a 256 -b)" || return 1
    echo "${output% *}"
  elif type openssl &>/dev/null; then
    output="$(openssl dgst -sha256)" || return 1
    echo "${output##* }"
  elif type sha256sum &>/dev/null; then
    output="$(sha256sum --quiet)" || return 1
    echo "${output% *}"
  else
    return 1
  fi
}

compute_md5() {
  local output
  if type md5 &>/dev/null; then
    md5 -q
  elif type openssl &>/dev/null; then
    output="$(openssl md5)" || return 1
    echo "${output##* }"
  elif type md5sum &>/dev/null; then
    output="$(md5sum -b)" || return 1
    echo "${output% *}"
  else
    return 1
  fi
}

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT
list="$tmpdir/list"
links="$tmpdir/links"
: > "$list"
: > "$links"

for meta in binaries/*.meta; do
  [ -e "$meta" ] || continue
  name="$(basename "$meta" .meta)"
  archive="$(sed -n 's/^archive=//p' "$meta")"
  case "$archive" in
  "" | *[!A-Za-z0-9._-]*)
    echo "Invalid archive name in $meta" >&2
    exit 1
    ;;
  esac
  if [ ! -f "binaries/$archive" ] || [ ! -f "binaries/$name" ]; then
    echo "Missing archive or definition for $name" >&2
    exit 1
  fi
  sha="$(compute_sha2 < "binaries/$archive")"
  printf '%s\n%s\n' "$archive" "$sha" >> "$links"
  printf '<li><a href="binaries/%s">%s</a> (<a href="binaries/%s">definition</a>)</li>\n' \
    "$archive" "$archive" "$name" >> "$list"
done

for file in source/*; do
  [ -e "$file" ] || continue
  base="$(basename "$file")"
  #md5="$(compute_md5 < "$file")"
  sha="$(compute_sha2 < "$file")"
  #ln -f "$file" "$md5"
  ln -f "$file" "$sha"
  sed -i -e "/>$base</s/^.*$/<li><a href=\"$sha\">$base<\/a><\/li>/" index.html
done

while IFS= read -r archive && IFS= read -r sha; do
  ln -f "binaries/$archive" "$sha"
done < "$links"

awk -v list="$list" '
  /<ul id="prebuilt-cpython">/ {
    print
    while ((getline line < list) > 0) print line
    close(list)
    replacing = 1
    next
  }
  replacing && /<\/ul>/ { replacing = 0 }
  !replacing { print }
' index.html > index.html.tmp
mv index.html.tmp index.html

# vim:set ft=sh :
