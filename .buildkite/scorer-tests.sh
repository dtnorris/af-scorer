#!/usr/bin/env bash
set -euo pipefail

scorer_commit="$(git rev-parse HEAD)"
spec_commit=394a44c2c2052ce2eeb6d28cd7647ad8a50acfcf
job_root="$(mktemp -d "${TMPDIR:-/tmp}/af-scorer-ci.XXXXXXXX")"
trap 'rm -rf -- "$job_root"' EXIT
job_root="$(cd "$job_root" && pwd -P)"

# Reproduce the scorer's sibling checkout layout in a directory unique to this job.
git init -q "$job_root/af-cli-scoring-utility"
git -C "$job_root/af-cli-scoring-utility" fetch -q --depth=1 "$PWD" "$scorer_commit"
git -C "$job_root/af-cli-scoring-utility" checkout -q --detach FETCH_HEAD

git init -q "$job_root/af-specification-md"
git -C "$job_root/af-specification-md" fetch -q --depth=1 \
  https://github.com/dtnorris/af-specification-md.git "$spec_commit"
git -C "$job_root/af-specification-md" checkout -q --detach FETCH_HEAD

test "$(git -C "$job_root/af-specification-md" rev-parse HEAD)" = "$spec_commit"
test -r "$job_root/af-specification-md/documents.json"

owner_commit=3611758b7dadfb88f46d011aa3b35c3dda575c62
git init -q "$job_root/af-source-md"
git -C "$job_root/af-source-md" fetch -q --depth=1 https://github.com/dtnorris/af-source-md.git "$owner_commit"
git -C "$job_root/af-source-md" checkout -q --detach FETCH_HEAD
test "$(git -C "$job_root/af-source-md" rev-parse HEAD)" = "$owner_commit"
export AF_SOURCE_MD_ROOT="$job_root/af-source-md"

cd "$job_root/af-cli-scoring-utility"
test "$(git rev-parse HEAD)" = "$scorer_commit"
git rev-parse HEAD
ruby --version
bundle --version
bundle install
bundle exec ruby -I"$AF_SOURCE_MD_ROOT/lib" "$AF_SOURCE_MD_ROOT/test/mechanics_test.rb"
bundle exec rake test
git diff --exit-code -- Gemfile.lock
git diff --check
