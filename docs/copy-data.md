# Copy data between servers

Copy images, volumes and large files to a new Dokploy server. The numbers are
from copies between two servers on one tailnet.

## Copy images

Images built on the old server have to reach the new one. This copied 8 images,
5.7 GB, in 9 minutes 50 seconds, about 15 MB/s over a tailnet:

```sh
docker save <images> | gzip -1 | ssh web2 'gunzip | docker load'
```

The image IDs differ on the two servers, because a classic image store and a
containerd store name the same image differently. The layer lists matched for
all 8:

```sh
docker image inspect --format '{{json .RootFS.Layers}}' <image>
```

## Copy a volume

Copy volumes and host paths after a clean stop:

```sh
docker run --rm -v vol:/v:ro alpine tar cf - -C /v . \
  | ssh web2 'docker run --rm -i -v vol:/v alpine tar xf - --numeric-owner -C /v'
```

For a host path, mount the path in the first container and extract with
`sudo tar xf - --numeric-owner -p -C <path>` on the new server. Row counts
matched on three databases after a copy.

A `docker run` client that was killed left its container running. Its `tar`
wrote the whole stream into the container's log and filled the disk. Check with
`docker ps` after you stop a copy.

## Copy speed

The tailnet copy was limited by `tailscaled`, which used 100% of one core on the
receiving server. `ssh` reached about 15 MB/s. Four parallel streams and plain
TCP both totalled 10 to 14 MB/s.

### One large file

```sh
rsync -a -z --compress-choice=zstd --compress-level=1 --partial-dir=DIR SRC DEST
```

`SRC` is the file, `DEST` the destination, and `DIR` the directory that holds
the partial file between runs.

This moved a 40 GB SQLite file at 24-27 MB/s of file data (10-11 MB/s on the
wire, about 2.2:1) over the same link: 30 minutes for the transfer, plus a
parallel sha256 check on both ends after.

It replaces hand-cut chunking with
`dd skip=N | zstd | ssh | zstd -d | dd seek=N`. It resumes on its own, and a
second run against the same destination sends only the changed bytes. While it
runs, the growing file sits under a hidden temporary name in the destination
directory, not the final name.

rsync-ing a database file while it is live can tear it. It is only safe when the
file was idle, mtime unchanged and WAL empty, before and after, or against a
service quiesced first.

### Many small files

One reader (`tar`) was disk-bound at about 500 files/s. Run 8 parallel readers
first, to warm the page cache before `tar` runs:

```sh
find -print0 | xargs -0 -P 8 -n 200 cat >/dev/null
```

That took the whole job from 47-48 minutes to a few minutes: 683,417 files
warmed in about 4 minutes, then streamed from cache.

`ionice` had no effect on a disk whose scheduler is `none`. Only BFQ honours I/O
classes, so check `/sys/block/<dev>/queue/scheduler` before relying on it.
`nice` still throttled CPU regardless of scheduler.
