#!/usr/bin/env bash
#
# unflatten-zip.sh
#
# Rebuilds a real directory tree from files whose names contain literal
# backslashes -- the mess you get when a Windows-made ZIP uses "\" as its
# path separator and a Linux extractor treats it as an ordinary character.
#
#   before:  ASAdventurer\public\app.js   (one file, flat)
#   after:   ASAdventurer/public/app.js   (nested, as intended)
#
# Usage:
#   ./unflatten-zip.sh [-n] [-y] [DIR]
#
#   -n, --dry-run   show what would happen, change nothing
#   -y, --yes       skip the confirmation prompt
#   -h, --help      this message
#   DIR             directory to fix (default: current directory)
#
set -euo pipefail

DRY_RUN=0
ASSUME_YES=0
TARGET_DIR="."

usage() {
	sed -n '3,20p' "$0" | sed 's/^# \{0,1\}//'
	exit "${1:-0}"
}

while [ $# -gt 0 ]; do
	case "$1" in
		-n | --dry-run) DRY_RUN=1 ;;
		-y | --yes) ASSUME_YES=1 ;;
		-h | --help) usage 0 ;;
		-*)
			printf 'unknown option: %s\n\n' "$1" >&2
			usage 1 >&2
			;;
		*) TARGET_DIR="$1" ;;
	esac
	shift
done

[ -d "$TARGET_DIR" ] || {
	printf 'not a directory: %s\n' "$TARGET_DIR" >&2
	exit 1
}
cd "$TARGET_DIR"

# ---------------------------------------------------------------- find work

# -depth so that contents are handled before their containing directory,
# in case a directory name also contains backslashes.
mapfile -d '' -t items < <(find . -depth -name '*\\*' -print0)

if [ "${#items[@]}" -eq 0 ]; then
	printf 'No filenames contain backslashes -- nothing to rebuild.\n'
	exit 0
fi

# ---------------------------------------------------------------- build plan

srcs=()
dsts=()
skips=()

for src in "${items[@]}"; do
	base="${src##*/}" # the component holding the backslashes
	parent="${src%/*}"
	[ "$parent" = "$src" ] && parent="."

	fixed="${base//\\//}"     # backslashes -> slashes
	fixed="${fixed#/}"        # no leading slash
	fixed="${fixed%/}"        # no trailing slash
	while [[ "$fixed" == *//* ]]; do
		fixed="${fixed//\/\//\/}" # collapse doubles
	done

	if [ -z "$fixed" ]; then
		skips+=("$src -- name is only separators")
		continue
	fi

	dst="$parent/$fixed"

	if [ -e "$dst" ]; then
		skips+=("$src -- destination already exists: $dst")
		continue
	fi

	# A plain FILE sitting where we need a DIRECTORY blocks the rebuild.
	blocked=""
	probe="$(dirname "$dst")"
	while [ "$probe" != "." ] && [ "$probe" != "/" ]; do
		if [ -e "$probe" ] && [ ! -d "$probe" ]; then
			blocked="$probe"
			break
		fi
		probe="$(dirname "$probe")"
	done
	if [ -n "$blocked" ]; then
		skips+=("$src -- a file blocks the path at: $blocked")
		continue
	fi

	srcs+=("$src")
	dsts+=("$dst")
done

# ---------------------------------------------------------------- show plan

printf '%s\n' "--- plan ---"
for i in "${!srcs[@]}"; do
	printf '  %s\n    -> %s\n' "${srcs[$i]#./}" "${dsts[$i]#./}"
done

if [ "${#skips[@]}" -gt 0 ]; then
	printf '\n--- skipped (%d) ---\n' "${#skips[@]}"
	printf '  %s\n' "${skips[@]}"
fi

printf '\n%d to move, %d skipped.\n' "${#srcs[@]}" "${#skips[@]}"

[ "${#srcs[@]}" -eq 0 ] && exit 0

if [ "$DRY_RUN" -eq 1 ]; then
	printf 'Dry run -- nothing changed.\n'
	exit 0
fi

if [ "$ASSUME_YES" -eq 0 ]; then
	printf '\nProceed? [y/N] '
	read -r reply
	case "$reply" in
		[yY] | [yY][eE][sS]) ;;
		*)
			printf 'Aborted.\n'
			exit 0
			;;
	esac
fi

# ---------------------------------------------------------------- execute

moved=0
failed=0
for i in "${!srcs[@]}"; do
	src="${srcs[$i]}"
	dst="${dsts[$i]}"
	if mkdir -p "$(dirname "$dst")" && mv -n -- "$src" "$dst"; then
		moved=$((moved + 1))
	else
		printf 'FAILED: %s\n' "$src" >&2
		failed=$((failed + 1))
	fi
done

printf '\nMoved %d' "$moved"
[ "$failed" -gt 0 ] && printf ', %d failed' "$failed"
printf '.\n'

# Clean up any now-empty directories left behind.
find . -depth -type d -empty -not -path . -delete 2>/dev/null || true

# ---------------------------------------------------------------- next steps

printf '\n--- result ---\n'
if command -v tree >/dev/null 2>&1; then
	tree -L 2 -a
else
	ls -la
fi

if pkg="$(find . -maxdepth 3 -name package.json -print -quit)" && [ -n "$pkg" ]; then
	printf '\nFound %s -- this may be an Electron/Node app that can run\n' "${pkg#./}"
	printf 'natively on Linux instead of through Wine. Worth checking:\n'
	printf '  cat %s\n' "${pkg#./}"
fi
