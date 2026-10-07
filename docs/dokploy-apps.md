# Move Dokploy applications

Move applications to a new Dokploy server after
[restoring the Dokploy database](./dokploy-move.md#restore-the-dokploy-database).
Images and volumes travel separately, see
[Copy data between servers](./copy-data.md). This was checked between two
Dokploy 0.30.7 servers.

## Deploy an image that exists only locally

A Docker-image application runs `docker pull` on every deploy. An image that
exists only in the local store fails with
`pull access denied ... repository does not exist`, and nothing is created. A
registry on the loopback address fixes it:

```sh
docker run -d --name registry --restart unless-stopped \
  -p 127.0.0.1:5000:5000 -v registry-data:/var/lib/registry registry:3
docker tag app:latest 127.0.0.1:5000/app:1
docker push 127.0.0.1:5000/app:1
```

Set `127.0.0.1:5000/app:1` as the application's image. Docker allows a loopback
registry over HTTP, and the pull reported the image as up to date straight away.
Turn the application's automatic deploy off, because it has no repository to
watch.

## Move a compose application

A compose application that builds from a repository has nothing to build from
once the repository is gone. Set its source to `raw`, paste the compose file as
it was at the deployed commit, and replace each `build:` with an `image:` from
the loopback registry above.

Volumes and host paths do not come across.
[Copy a volume](./copy-data.md#copy-a-volume) says how. Compose uses volumes
that were created ahead of it and prints only a warning that it did not create
them.

## Deploy a file mount

A Dokploy file mount is a database row that holds the content. Its file,
`/etc/dokploy/applications/<app name>/files`, was not on the new server after
the restore, and the service was rejected with
`bind source path does not exist`. Calling `mounts.update` with the same content
wrote nothing, because the row has no `filePath`. Copying the file from the old
server fixed it, and the two files had the same sha256.

## Names on a shared network

A container on a private network and on `dokploy-network` resolves a name in
either. On the new server the name `postgres` resolved to the database of
another application on `dokploy-network`, not to the application's own. That
database logged about 1,000 `sorry, too many clients already` and 283
`canceling authentication due to timeout` in five minutes. The application's own
database logged nothing. Use the container's full name, such as
`<project>-postgres-1`, in the connection string.

A container on the default bridge could not resolve tailnet names. A container
on `dokploy-network` could, and it also resolved another container by its name.
