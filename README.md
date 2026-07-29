# unflatten-zip

Rebuilds a real directory tree from files whose names contain literal backslashes.

```
before:  myapp\assets\sounds\chime.mp3   ← one file, flat
after:   myapp/assets/sounds/chime.mp3   ← nested, as intended
```

## Why

The ZIP format uses forward slashes as the path separator. Some archives are
written with Windows-style backslashes instead, storing entry names like
`myapp\assets\config.json`.

Windows extractors accept either and build the folder tree you'd expect. On
Linux and macOS a backslash is a legal character in a filename, so the extractor
has no way to know it was meant as a separator — it creates one file literally
named `myapp\assets\config.json` in the current directory. No subfolders are
created, and everything lands in one flat pile.

This script converts those names back into directories.

## Requirements

Bash 4.0+ and coreutils. No dependencies. `tree` is used for the summary at the
end if you have it, and skipped if you don't.

## Install

```bash
curl -O https://raw.githubusercontent.com/BrokenAnsible/unflatten-zip/main/unflatten-zip.sh
chmod +x unflatten-zip.sh
```

## Usage

Preview first:

```bash
./unflatten-zip.sh -n ~/some/flat/directory
```

Then run it:

```bash
./unflatten-zip.sh ~/some/flat/directory
```

With no directory argument it operates on the current directory.

| Flag | Effect |
| --- | --- |
| `-n`, `--dry-run` | Print the plan and exit without changing anything |
| `-y`, `--yes` | Skip the confirmation prompt |
| `-h`, `--help` | Usage summary |

### Example

```
$ ./unflatten-zip.sh -n
--- plan ---
  myapp\index.html
    -> myapp/index.html
  myapp\assets\sounds\chime.mp3
    -> myapp/assets/sounds/chime.mp3
  ...

15 to move, 0 skipped.
Dry run -- nothing changed.
```

## Safety

Moving a large number of files based on pattern matching deserves some caution,
so the script is deliberately conservative:

- **Dry-run mode** shows the complete plan before you commit to it.
- **Confirmation prompt** by default; `-y` opts out.
- **Never overwrites.** Moves use `mv -n`. If a destination already exists, that
  file is skipped and reported instead.
- **Detects blocked paths.** If a plain file occupies a location the script needs
  to use as a directory, it skips that entry and tells you which path is in the
  way, rather than failing partway through.
- **Idempotent.** Running it twice is harmless; the second pass finds nothing to
  do and exits.
- **Reports everything skipped**, with the reason, so nothing disappears quietly.

Only empty directories are removed, and only after all moves complete.

## How it works

1. `find -depth -name '*\\*'` locates every entry with a backslash in its name.
   Depth-first ordering means directory contents are handled before the
   directories containing them, in case a directory name is also affected.
2. Backslashes in the final path component are converted to forward slashes;
   leading, trailing, and duplicated separators are normalized away.
3. Each move is checked for collisions and blocked paths, then added to the plan
   or the skip list.
4. The plan is displayed. After confirmation, parent directories are created and
   each file is moved with `mv -n`.
5. Empty directories are cleaned up and the resulting tree is printed.

## Limitations

- Only the final path component is rewritten. Backslashes in an intermediate
  directory name are handled by the depth-first pass, but archives mixing both
  separator styles at several levels may need a second run.
- Filenames containing a genuine, intentional backslash will be rewritten too.
  Use `-n` first.
- Permissions and timestamps come from the extraction, not from this script.

## License

MIT
