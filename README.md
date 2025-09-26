# configure.ps1

PowerShell script that keeps a set of local directories in sync with symbolic links defined in `mappings.txt`.

## Requirements

- Windows with Developer Mode enabled so directory symbolic links can be created without elevation.
- PowerShell 7+ (Windows PowerShell also works).

## Usage

1. Place `configure.ps1` and a `mappings.txt` file in the same directory.
2. Populate `mappings.txt` with one mapping per line using the format `LOCAL_NAME: TARGET`.
3. Run the script from that directory:
   ```powershell
   pwsh ./configure.ps1
   ```

Optional: pass a custom mapping file with `-MappingsPath`.

## Mapping File Rules

- Lines that are empty or only whitespace are ignored.
- Inline comments starting with `#` are stripped before parsing (e.g. `Test3: %USERPROFILE%\Foo # note`).
- `LOCAL_NAME` is always resolved relative to the script directory.
- `TARGET` can include environment variables in the Windows style (`%VAR%`) which are expanded before resolution (relative paths remain script-relative).
- Quotes around `TARGET` are removed if present.

## Processing Logic

For each mapping the script:

- **Target already correct**: If `LOCAL_NAME` exists and `TARGET` is a symbolic link pointing at it, nothing changes.
- **Relink**: If `LOCAL_NAME` exists and `TARGET` is a symbolic link to a different location, the link is recreated to point at `LOCAL_NAME`.
- **Create link**: If `LOCAL_NAME` exists and `TARGET` is missing, a symbolic link is created at `TARGET` pointing at `LOCAL_NAME`. Missing parent directories are created automatically.
- **Adopt existing target**: If `LOCAL_NAME` is missing and `TARGET` exists (not a link), `TARGET` is moved into the script directory using name `LOCAL_NAME`, then a symbolic link is created back at `TARGET`.
- **Create new local directory**: If both `LOCAL_NAME` and `TARGET` are missing, a directory named `LOCAL_NAME` is created under the script directory and a symbolic link is created at `TARGET` pointing to it.
- **Error cases** (reported and the script exits with status 1 if any occur):
  - `LOCAL_NAME` exists and `TARGET` exists but is not a symbolic link.
  - `LOCAL_NAME` is missing while `TARGET` is a symbolic link.
  - Formatting errors or paths that cannot be resolved.

The script logs each action and reports warnings when it cannot satisfy a mapping. Any warning triggers a non-zero exit code so automation can detect problems.
