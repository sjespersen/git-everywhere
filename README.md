# git-everywhere

> **Experimental.** Try it on a copy or a test folder first, and keep your usual backups.

Version control for directories you can only reach via SFTP, FTP, WebDAV, S3 or any other storage
[rclone](https://rclone.org) supports. For example cheap web hosting without SSH access.

The command is `git-everywhere`, with the short alias `gite`. Since it is named `git-<something>`,
`git everywhere` works as well.

Git needs a computer to do its work, but the server does not have to be that computer.
git-everywhere does all the git work on your machine and uses the server only as storage:

1. **Download**: rclone compares the server with your local copy (size and modification time) and downloads only what changed.
2. **Commit**: plain git commits the new state locally.
3. **Upload history**: the new commits go to the server as one [git bundle](https://git-scm.com/docs/git-bundle) file, next to your files.
4. **Restore**: check out an old commit locally and upload the difference.

Nothing is installed or executed on the server.

## Install

You need `bash` (3.2 or newer), `git` (2.28 or newer) and `rclone` (1.66 or newer).

```sh
brew install rclone            # or see https://rclone.org/install/
curl -o ~/bin/git-everywhere https://raw.githubusercontent.com/sjespersen/git-everywhere/main/git-everywhere
chmod +x ~/bin/git-everywhere
ln -s git-everywhere ~/bin/gite   # optional short alias
```

Set up a connection to your server once with `rclone config`, e.g. an SFTP remote named `myhost`.

## Usage

```sh
git-everywhere init myhost:htdocs mysite --exclude '/cache/**' --exclude '/uploads/**'
cd mysite

git-everywhere status          # what changed on the server since the last snapshot?
git-everywhere snapshot -m "before plugin update"

git log --stat                 # it is a normal git repository
git diff HEAD~1 -- index.php

git-everywhere restore HEAD~1  # put the server back, asks before uploading
gite snapshot                  # the same, with the short alias
```

| Command | What it does |
|---|---|
| `init <remote> [<dir>] [--history <remote>] [--exclude <pattern>]…` | Create a local copy and the first snapshot. If history already exists on the server, it is downloaded instead. |
| `snapshot [-m <msg>]` | Download changes from the server, commit them and upload the history. Run it before and after you change something, or from cron. |
| `status` | Show changed (`~`), new (`+`) and deleted (`-`) files on the server. |
| `restore <rev> [--yes]` | Take a snapshot, then make the server match `<rev>`. Shows the changes and asks first. The restore is a new commit, nothing is lost. |
| `fetch` | Download new history, e.g. when you also work from another machine. |
| `uninstall [--yes]` | Delete the history from the server after asking. Your files there are not touched. The local copy stays as a plain git repository with the full history; delete its folder if you no longer need it. Refuses if the server has commits your copy does not have (`fetch` first). |

Extra rclone flags go into `RCLONE_FLAGS`, e.g. `RCLONE_FLAGS="--checksum -v" git-everywhere snapshot`.

## Where things are

| Where | What |
|---|---|
| `<remote>` | your files, untouched except by `restore` |
| `<remote>.git-everywhere/` | the history, e.g. `myhost:htdocs.git-everywhere`. Choose another place with `--history`. |
| `<remote>.git-everywhere/bundles/000001-<commit>.bundle` | one file per snapshot with the commits since the previous one. Files are only added, never changed. |
| `<remote>.git-everywhere/everywhere-filter` | the shared exclude rules |
| `<remote>.git-everywhere/.git-everywhere-history` | marker file: rclone never syncs a folder containing it, so the history is safe even inside the synced folder |
| `<dir>/` | local copy of the files, a normal git work tree |
| `<dir>/.git/config` | `everywhere.remote`, `everywhere.history` (local only) |
| `<dir>/.git/everywhere-filter` | [rclone filter rules](https://rclone.org/filtering/) |

Files are stored byte for byte: `.gitignore` and `.gitattributes` files on the server are ignored,
line endings are not converted, and git repositories on the server (e.g. a plugin installed with
`git clone`) are versioned as plain files, without their `.git` folder.

The history folder gets an `.htaccess` with `Require all denied`, because on many hosts it lies below the
web root. Check that your server honours it (Apache does), or put the history somewhere that is not served
with `--history`.

Since the history is plain git bundles, you can always get it back without git-everywhere:
download the bundles and run `git fetch <bundle> main` for each of them in order.

## Limitations

- **One writer at a time.** FTP has no locks. git-everywhere refuses to upload when the server has history
  your copy does not know (`fetch` first), but two snapshots running at the same moment can still collide.
- **Change detection uses size and modification time.** Some FTP servers report times with low precision.
  Use `RCLONE_FLAGS=--checksum` where the server supports hashes, or `--download` to compare contents.
- **Excludes should be set at `init`.** Files that are already in the history and get excluded later show up
  as deleted in copies made afterwards. Remove them from git with `git rm -r --cached <path>` when you
  change the filter.
- **It is slow.** Every command opens new connections and lists the whole remote directory to find changes.
  Over SFTP that is several seconds even when nothing changed, and the first snapshot downloads every file.
  Expect minutes for a site with thousands of files. Excluding uploads, caches and other large or
  generated folders helps most.
- **It needs a lot of space.** Locally you keep a full copy of all files plus the git history, so at least
  twice the size of the site, growing with every change. On the server the first bundle holds a compressed
  copy of everything, and every snapshot adds another bundle that is never deleted.
- **File names that differ only in case** (`README.txt` and `readme.txt`) cannot both be stored on a
  case-insensitive disk (macOS, Windows). rclone warns about it, only one of them is versioned.
- **S3 and similar:** for a remote that is only a bucket (`s3:bucket`), the default history location would
  be another bucket. Give `--history s3:bucket/.git-everywhere` instead.
- **Databases are not covered.** Dump them into the directory before a snapshot if you want them versioned.
- The history lives with the same provider as your files. It is not an off-site backup, but your local
  copy is.

## Tests

```sh
tests/run.sh           # the main workflow
tests/regressions.sh   # one test per bug found so far
```

Both use local directories as the server. It has also been tried against SFTP web hosting.

## License

MIT, see [LICENSE](LICENSE).
