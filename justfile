# Task runner for service-mesh-api. Run `just` with no arguments to see the menu.
#
# Every recipe runs its tools through `mise exec` so it uses the versions pinned
# in mise.toml without relying on the shell's mise activation.
lychee := "mise exec -- lychee"

# The version in VERSION, which names the release tag
version := `cat VERSION`

# List all recipes
default:
    @just --list

# Check every relative link and anchor in the Markdown files (matches CI)
[group('checks')]
check:
    {{lychee}} --offline --include-fragments --no-progress '*.md'

# Check every link in the Markdown files, including external ones
[group('checks')]
links:
    {{lychee}} --include-fragments --no-progress '*.md'

# Refuses a working tree with changes and a VERSION that is not vX.Y.Z.
#
# Tag the current commit with the version in VERSION and push the tag
[group('release')]
release:
    echo "{{version}}" | grep -Eq '^v[0-9]+\.[0-9]+\.[0-9]+$' || (echo "VERSION must look like v1.2.3" && exit 1)
    test -z "$(git status --porcelain)" || (echo "commit or stash your changes first" && exit 1)
    git tag -a {{version}} -m "{{version}}"
    git push origin {{version}}

# Bump the version in VERSION by one patch, minor, or major step and commit that file: just bump patch
[group('release')]
bump part:
    #!/usr/bin/env bash
    set -euo pipefail
    current="$(cat VERSION)"
    current="${current#v}"
    IFS=. read -r major minor patch <<< "$current"
    case "{{part}}" in
      patch) patch=$((patch + 1)) ;;
      minor) minor=$((minor + 1)); patch=0 ;;
      major) major=$((major + 1)); minor=0; patch=0 ;;
      *) echo "part must be patch, minor, or major" >&2; exit 1 ;;
    esac
    next="${major}.${minor}.${patch}"
    echo "v$next" > VERSION
    git commit -q -m "Release v$next" -- VERSION
    echo "v$current -> v$next, committed"
