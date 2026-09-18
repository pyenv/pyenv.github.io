#!/usr/bin/env bats

setup() {
  site="$BATS_TEST_TMPDIR/site"
  mkdir -p "$site/binaries"
  cp "$BATS_TEST_DIRNAME/../update.sh" "$BATS_TEST_DIRNAME/../index.html" "$site"
  cd "$site" || return
}

write_meta() {
  local name="$1"
  local archive="$2"
  cat > "binaries/$name.meta" <<EOF
# pyenv-binary metadata
version=${name%%-*}
os=Linux
arch=x86_64
platform=linux-x86_64
distro=ubuntu 24.04
libc=glibc 2.39
build_prefix=/tmp/pyenv/versions/$name
archive=$archive
EOF
}

write_binary() {
  local name="$1"
  local archive="$2"
  local contents="$3"
  printf '%s' "$contents" > "binaries/$archive"
  printf definition > "binaries/$name"
  write_meta "$name" "$archive"
}

write_archives() {
  write_binary 3.14.0-ubuntu-24.04-x86_64 \
    3.14.0-ubuntu-24.04-x86_64.tar.xz archive-data
  write_binary 3.13.0-ubuntu-24.04-x86_64 \
    3.13.0-ubuntu-24.04-x86_64.tar.gz gzip-archive-data
}

assert_success() {
  [ "$status" -eq 0 ]
}

assert_failure() {
  [ "$status" -ne 0 ]
}

@test "indexes xz and gzip prebuilt archives" {
  write_archives

  run bash ./update.sh
  assert_success

  xz_sha=8a6111c3ca752ed6d5f8e8a6daa3ba4b8c3b0bf55f00a87ac2b285024ef87e5f
  [ binaries/3.14.0-ubuntu-24.04-x86_64.tar.xz -ef "$xz_sha" ]
  xz_entry='<li><a href="binaries/3.14.0-ubuntu-24.04-x86_64.tar.xz">3.14.0-ubuntu-24.04-x86_64.tar.xz</a> (<a href="binaries/3.14.0-ubuntu-24.04-x86_64">definition</a>)</li>'
  grep -Fqx "$xz_entry" index.html

  gzip_sha=c809857f5fa564e1a2fdb3618161114bfb9a9c624ade6b580f6d79df0adfcc26
  [ binaries/3.13.0-ubuntu-24.04-x86_64.tar.gz -ef "$gzip_sha" ]
  gzip_entry='<li><a href="binaries/3.13.0-ubuntu-24.04-x86_64.tar.gz">3.13.0-ubuntu-24.04-x86_64.tar.gz</a> (<a href="binaries/3.13.0-ubuntu-24.04-x86_64">definition</a>)</li>'
  grep -Fqx "$gzip_entry" index.html
}

@test "repeated updates do not duplicate entries" {
  write_archives
  bash ./update.sh
  cp index.html index.before

  run bash ./update.sh
  assert_success

  cmp -s index.before index.html
  [ "$(grep -Fc '3.14.0-ubuntu-24.04-x86_64.tar.xz</a>' index.html)" -eq 1 ]
  [ "$(grep -Fc '3.13.0-ubuntu-24.04-x86_64.tar.gz</a>' index.html)" -eq 1 ]
}

@test "rejects unsafe archive names before updating files" {
  write_archives
  printf 'archive=bad\narchive=name.tar.gz\n' > binaries/z-invalid.meta
  printf definition > binaries/z-invalid
  mkdir source
  printf source-data > source/example.tar.gz
  printf '<li><a href="">example.tar.gz</a></li>\n' >> index.html
  cp -R . "$BATS_TEST_TMPDIR/site.before"

  run bash ./update.sh
  assert_failure

  [[ "$output" == *"Invalid archive name in binaries/z-invalid.meta"* ]]
  diff -r "$BATS_TEST_TMPDIR/site.before" .
}

@test "uses a safe archive name from metadata" {
  write_binary custom-definition python-build.tar.xz archive-data

  run bash ./update.sh
  assert_success

  entry='<li><a href="binaries/python-build.tar.xz">python-build.tar.xz</a> (<a href="binaries/custom-definition">definition</a>)</li>'
  grep -Fqx "$entry" index.html
}

@test "rejects a missing definition" {
  write_binary 3.14.0-ubuntu-24.04-x86_64 \
    3.14.0-ubuntu-24.04-x86_64.tar.xz archive-data
  rm binaries/3.14.0-ubuntu-24.04-x86_64

  run bash ./update.sh
  assert_failure
}

@test "rejects a missing archive" {
  write_binary 3.14.0-ubuntu-24.04-x86_64 \
    3.14.0-ubuntu-24.04-x86_64.tar.xz archive-data
  rm binaries/3.14.0-ubuntu-24.04-x86_64.tar.xz

  run bash ./update.sh
  assert_failure
}
