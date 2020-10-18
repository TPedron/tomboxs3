# Tomboxs3

## Project Description
This ruby app monitors a directory (called the magic dir) for changes and ensures any changes are synced to a remote s3 bucket. Right now this app only supports syncing changes that occur in the local magic dir to the remote s3 bucket but not the other way around. I plan to handle that in the future though.

It keeps a `s3_manifest.json` file in the magic dir (this file is ignored when monitoring) which stores data about each file to be synced.  We essentially diff this with the point-in-time contents of the remote s3 bucket and perform file actions to put them in the same state. A signed url to share the files is stored in here but does expire.

## Configuration

Modify the `run_tombox.sh` script to configure your Bucket info and magic directory ENV vars.

Also you must set your AWS `aws_access_key_id` and `aws_secret_access_key` values (preferably in `~/.aws/credentials`), see: https://docs.aws.amazon.com/sdk-for-ruby/v3/developer-guide/setup-config.html

The following env vars are EXPORTed in the `run_tombox.sh` file.

- `DEBUG_LOGGING` - Defaults to `"FALSE`.
- `BUCKET_NAME` - Your bucket name, must be set.
- `REGION` - Your bucket's region, must be set.
- `MANIFEST_FILE_NAME` - This file lives in magic dir, defaults to `"s3_manifest.json"`.
- `MAGIC_DIR_PATH`- The path to the dir to monitor, must be set.

## Usage
Run the following shell script to download dependencies and continuously monitor the directory.

```
./run_tombox.sh
```

## Change Log

### v0.1 - Oct 18 2020

Description: Cutting a first release since its in a working state for my uses (basic client-side changes)
Features:
- Uploads new local files to remote s3 with md5 saved in metadata
- Syncs new versions of local files to remote s3 on update
- Delete of local file deletes file on remote
- Manifest generation with md5s saved
- Run sync on update of local dir
- Write ReadMe with full setup instructions

## Future Features
- Optimize script and usage of listen
- Add support for folders + recursive checks
- Support for detecting changes to remote s3 and syncing changes back to local (logic below)
    - Handle deletions from remote
        - When file exists in manifest but and local but not s3
    - Handle new files from remote
        - When file exists in s3 but not local or manifest
    - Handle updates from remote
        - When file exists in local, manifest and s3 s3.local.last_modified > local.last_modified
        - Remote may or may not have an md5 (could be uploaded straight to s3
        - If MD5 missing, update local with remote file and then update remote with md5 metadata
    - Run local sync when remote change occurs
- Right click on file button to get sharable link (this link can be manually retrieved from the manifest file)
    - This can be done simply as a Mac Automator custom service https://apple.stackexchange.com/questions/232205/how-to-create-an-automator-service-to-run-a-script-on-all-files-in-a-folder
- Upload archives of files?
