#!/bin/bash
##===----------------------------------------------------------------------===##
##
## This source file is part of the Swift Distributed Tracing Baggage
## open source project
##
## Copyright (c) 2020-2021 Apple Inc. and the Swift Distributed Tracing Baggage
## project authors
## Licensed under Apache License v2.0
##
## See LICENSE.txt for license information
##
## SPDX-License-Identifier: Apache-2.0
##
##===----------------------------------------------------------------------===##

set -e

my_path="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
declare -r root_path="$my_path/.."
version=$(git describe --abbrev=0 --tags || echo "0.0.0")
declare -r modules=(InstrumentationBaggage)
main_module="InstrumentationBaggage"
declare -r project_xcodeproj_name="swift-distributed-tracing-baggage"
declare -r project_gh_name="swift-distributed-tracing-baggage"

if [[ "$(uname -s)" == "Linux" ]]; then
  # build code if required
  if [[ ! -d "$root_path/.build/x86_64-unknown-linux-gnu" ]]; then
    swift build
  fi
  # setup source-kitten if required
  source_kitten_source_path="$root_path/.build/.SourceKitten"
  if [[ ! -d "$source_kitten_source_path" ]]; then
    git clone https://github.com/jpsim/SourceKitten.git "$source_kitten_source_path"
  fi
  source_kitten_path="$source_kitten_source_path/.build/x86_64-unknown-linux-gnu/debug"
  if [[ ! -d "$source_kitten_path" ]]; then
    rm -rf "$source_kitten_source_path/.swift-version"
    cd "$source_kitten_source_path" && swift build && cd "$root_path"
  fi
  # generate
  mkdir -p "$root_path/.build/sourcekitten"
  for module in "${modules[@]}"; do
    if [[ ! -f "$root_path/.build/sourcekitten/$module.json" ]]; then
      "$source_kitten_path/sourcekitten" doc --spm --module-name $module > "$root_path/.build/sourcekitten/$module.json"
    fi
  done
fi

[[ -d docs/$version ]] || mkdir -p docs/$version
[[ -d "$project_xcodeproj_name.xcodeproj" ]] || swift package generate-xcodeproj

# run jazzy
if ! command -v jazzy > /dev/null; then
  gem install jazzy --no-ri --no-rdoc
fi

jazzy_dir="$root_path/.build/jazzy"
rm -rf "$jazzy_dir"
mkdir -p "$jazzy_dir"

module_switcher="$jazzy_dir/README.md"
jazzy_args=(--clean
            --author 'Swift Distributed Tracing team'
            --readme "$module_switcher"
            --author_url https://github.com/apple/$project_gh_name
            --github_url https://github.com/apple/$project_gh_name
            --github-file-prefix https://github.com/apple/$project_gh_name/tree/$version
            --theme fullwidth
            --xcodebuild-arguments -scheme,$project_xcodeproj_name-Package)
cat > "$module_switcher" <<"EOF"
# Swift Distributed Tracing Baggage Docs
This project contains modules:
EOF

for module in "${modules[@]}"; do
  echo " - [$module](../$module/index.html)" >> "$module_switcher"
done

for module in "${modules[@]}"; do
  echo "processing $module"
  args=("${jazzy_args[@]}" --output "$jazzy_dir/docs/$version/$module" --docset-path "$jazzy_dir/docset/$version/$module"
        --module "$module" --module-version $version
        --root-url "https://apple.github.io/$project_gh_name/docs/$version/$module/")
  if [[ -f "$root_path/.build/sourcekitten/$module.json" ]]; then
    args+=(--sourcekitten-sourcefile "$root_path/.build/sourcekitten/$module.json")
  fi

  jazzy "${args[@]}"

  if [[ $(cat $root_path/.build/sourcekitten/$module.json) == "0" ]]; then
    echo "processing module $module ($root_path/.build/sourcekitten/$module.json) yielded EMPTY module json file!"
    exit 1
  fi
done

# push to github pages
if [[ $PUSH == true ]]; then
  BRANCH_NAME=$(git rev-parse --abbrev-ref HEAD)
  GIT_AUTHOR=$(git --no-pager show -s --format='%an <%ae>' HEAD)
  git fetch origin +gh-pages:gh-pages
  git checkout gh-pages
  rm -rf "docs/$version"
  rm -rf "docs/current"
  cp -r "$jazzy_dir/docs/$version" docs/
  cp -r "docs/$version" docs/current
  git add --all docs
  echo "<html><head><meta http-equiv=\"refresh\" content=\"0; url=\"docs/current/$main_module/index.html\" /></head></html>" > index.html
  git add index.html
  touch .nojekyll
  git add .nojekyll
  changes=$(git diff-index --name-only HEAD)
  if [[ -n "$changes" ]]; then
    echo -e "changes detected\n$changes"
    git commit --author="$GIT_AUTHOR" -m "publish $version docs"
    git push origin gh-pages
  else
    echo "no changes detected"
  fi
  git checkout -f $BRANCH_NAME
fi
