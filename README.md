# git-everywhere

Version control for directories you can only reach via SFTP, FTP, WebDAV, S3 or any other storage
[rclone](https://rclone.org) supports. For example cheap web hosting without SSH access.

Git needs a computer to do its work, but the server does not have to be that computer.
git-everywhere does all the git work on your machine and uses the server only as storage:

1. **Download**: rclone compares the server with your local copy (size and modification time) and downloads only what changed.
2. **Commit**: plain git commits the new state locally.
3. **Upload history**: the git history is copied to a folder next to the files on the server.
4. **Restore**: check out an old commit locally and upload the difference.

Nothing is installed or executed on the server.

## Install

You need `bash` (3.2 or newer), `git` (2.28 or newer) and `rclone`.

```sh
brew install rclone            # or see https://rclone.org/install/
curl -o ~/bin/git-everywhere https://raw.githubusercontent.com/<owner>/git-everywhere/main/git-everywhere
chmod +x ~/bin/git-everywhere
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
```

| Command | What it does |
|---|---|
| `init <remote> [<dir>] [--history <remote>] [--exclude <pattern>]…` | Create a local copy and the first snapshot. If history already exists on the server, it is downloaded. |
| `snapshot [-m <msg>]` | Download changes from the server and commit them. Run it before and after you change something, or from cron. |
| `status` | Show changed (`~`), new (`+`) and deleted (`-`) files on the server. |
| `restore <rev> [--yes]` | Take a snapshot, then make the server match `<rev>`. Shows the changes and asks first. The restore is a new commit, nothing is lost. |
| `fetch` | Download the history, e.g. when you also work from another machine. |

Extra rclone flags go into `RCLONE_FLAGS`, e.g. `RCLONE_FLAGS="--checksum -v" git-everywhere snapshot`.

## Where things are

| Where | What |
|---|---|
| `<remote>` | your files, untouched except by `restore` |
| `<remote>.git-everywhere` | the history, e.g. `myhost:htdocs.git-everywhere`. Choose another place with `--history`. |
| `<dir>/` | local copy of the files, a normal git work tree |
| `<dir>/.git/config` | `everywhere.remote`, `everywhere.history` (local only) |
| `<dir>/.git/everywhere-filter` | [rclone filter rules](https://rclone.org/filtering/), shared via the server |

The history folder gets an `.htaccess` with `Require all denied`, because on many hosts it lies below the
web root. Check that your server honours it (Apache does), or put the history somewhere that is not served
with `--history`.

## Limitations

- **One writer at a time.** FTP has no locks. git-everywhere refuses to upload when the server has history
  your copy does not know (`fetch` first), but two snapshots running at the same moment can still collide.
- **Change detection uses size and modification time.** Some FTP servers report times with low precision.
  Use `RCLONE_FLAGS=--checksum` where the server supports hashes (many SFTP servers do), or
  `--download` to compare contents.
- **Excludes should be set at `init`.** Files that are already in the history and get excluded later show up
  as deleted in copies made afterwards. Remove them from git with `git rm -r --cached <path>` when you
  change the filter.
- **Databases are not covered.** Dump them into the directory before a snapshot if you want them versioned.
- **The history only grows.** Copying to the server never deletes, so objects are kept loose and never packed.
- The history lives with the same provider as your files. It is not an off-site backup, but your local
  copy is.

## Tests

```sh
tests/run.sh
```

Uses a local directory as the server.

## License

MIT, see [LICENSE](LICENSE).
