# Configure Scripts

Companion scripts keep a set of local directories in sync with symbolic links defined in mapping files that live beside the scripts.

## Shared Mapping Rules

- Define mappings in `LOCAL_NAME: TARGET` format. `LOCAL_NAME` is treated as a path relative to the script directory.
- `mappings.txt` is always read when present. Platform-specific additions are loaded from `mappings.win.txt` on Windows and `mappings.nix.txt` on Linux/macOS. Entries are processed in the order they appear across files.
- Blank lines and trailing comments (`# comment`) are ignored.
- Quotes around the target path are stripped.
- Environment variables are expanded in both Windows (`%VAR%`) and Unix (`$VAR` / `${VAR}`) styles. On Windows, `$HOME` falls back to the user profile directory.

## Windows (`configure.ps1`)

- Requires Windows with Developer Mode enabled to create directory symbolic links without elevation.
- Works with PowerShell 7+ (Windows PowerShell also supported).
- Forward slashes in mapping paths are accepted and normalised.
- Run from the script directory:
  ```powershell
  pwsh ./configure.ps1
  ```
- Use `-MappingsPath` to supply an explicit mapping file instead of the default set.

## Linux/macOS (`configure`)

- Requires Bash 3.2+ (or newer) and standard Unix utilities (`mkdir`, `ln`, `mv`, `readlink`).
- Run from the script directory:
  ```bash
  ./configure
  ```
- Pass `--mappings PATH` to process a single, custom mapping file.

## Processing Logic

For each mapping the scripts perform the same steps:

- **Target already correct**: If `LOCAL_NAME` exists and `TARGET` is a symbolic link pointing at it, nothing changes.
- **Relink**: If `LOCAL_NAME` exists and `TARGET` is a symbolic link to a different location, the link is recreated to point at `LOCAL_NAME`.
- **Create link**: If `LOCAL_NAME` exists and `TARGET` is missing, a symbolic link is created at `TARGET` pointing at `LOCAL_NAME`. Missing parent directories are created automatically.
- **Adopt existing target**: If `LOCAL_NAME` is missing and `TARGET` exists (not a link), `TARGET` is moved into the script directory using name `LOCAL_NAME`, then a symbolic link is created back at `TARGET`.
- **Create new local directory**: If both `LOCAL_NAME` and `TARGET` are missing, a directory named `LOCAL_NAME` is created under the script directory and a symbolic link is created at `TARGET` pointing to it.
- **Error cases** (reported and the script exits with status 1 if any occur):
  - `LOCAL_NAME` exists and `TARGET` exists but is not a symbolic link.
  - `LOCAL_NAME` is missing while `TARGET` is a symbolic link.
  - Formatting errors or paths that cannot be resolved.

Each action is logged and any warning causes a non-zero exit code so automation can detect problems.
