# Sync Oracle Linux yum repos from ULN or yum.oracle.com

The `Dockerfile` and scripts in this repo create a container image that is able to sync content from both the [Unbreakable Linux Network][ULN] (ULN) and the [Oracle Linux yum server][YUM] to local repos with URL paths that match the ones on <https://yum.oracle.com>.

## Build the `ol-repo-sync` image (optional)

To build the `ol-repo-sync` image, clone this repo then run:

```bash
docker build -t ol-repo-sync .
```

To use the local image, remove `ghcr.io/djelibeybi` from each of the `docker run` commands provided below.

## Initial setup

An Oracle Linux support subscription is **required** to sync from ULN. If you do not have a support subscription, remove the `uln` array completely from the `config/repos.json` file.

Note that some repos are only available via ULN, including repos that contain the word `patch`, `ksplice`, `JavaSE` and `Exadata`.

For the best sync performance, add repos from the Oracle Linux yum server wherever possible, instead of the equivalent channel on ULN. The Oracle Linux yum server is cached by the Akamai CDN and generally provides a significantly greater download speed than ULN.

### Register with ULN (optional)

Before content can be synced from ULN, the container has to be registered. The following command will map the local `rhn/` directory to `/etc/sysconfig/rhn/` inside the container and then automatically register the container using the ULN credentials provided in `config/uln.conf`:

```bash
docker run --rm -it \
  --name ol-repo-sync-register \
  -v "$PWD/rhn:/etc/sysconfig/rhn" \
  -v "$PWD/config:/config" \
  ghcr.io/djelibeybi/ol-repo-sync register
```

This will take a few minutes with no output to the terminal but should return to the command prompt when completed.

If you mount a local directory to `/etc/sysconfig/rhn` each time you start a container, you should only have to register with ULN once, as the registration details are stored inside this directory.

> You can skip manual registration by running the container on an Oracle Linux host that is already registered with ULN and mounting the local `/etc/sysconfig/rhn` directory to the container.

Source packages are not synced by default. To include source packages, set the `SYNC_SRC` environment variable to `1` by passing `-e SYNC_SRC=1` as an argument to `docker run`.

### Store ULN credentials

To enable the automatic subscription and unsubscription of ULN channels, the sync process needs access to ULN credentials with permission to change channel subscriptions.

Copy [`config/uln.sample.conf`](./config/uln.sample.conf) to `config/uln.conf` and replace the placeholders with Oracle SSO credentials and an active CSI. To protect the content of this file, run `chmod 400 config/uln.conf` to prevent others from being able to see the credentials.

### Update map of available repos

The `config/repo-map.json` file contains a map of repo ID and URL for each repo available on the Oracle public yum server with the appropriate local file system path to ensure the same path structure is maintained locally.

To create or update the `config/repo-map.json` file, run:

```bash
docker run --rm -it \
  --name ol-repo-sync-update \
  -v "$PWD/config:/config" \
  ghcr.io/djelibeybi/ol-repo-sync update
```

This should be run regularly or at least whenever a new version of Oracle Linux is released to update the `config/repo-map.json` file.

### Configure the repos to sync

Copy [`config/repos.sample.json`](./config/repos.sample.json) to `config/repos.json` and add all the repos you want to sync to either the `uln` or `yum` array.

## Syncing repos

The following command will sync the content of the repos configured in `config/repos.json` to the `$PWD/repo` directory which is mounted at `/repo` inside the container.

```bash
docker run --rm -it \
  --name ol-repo-sync \
  -v "$PWD/rhn:/etc/sysconfig/rhn" \
  -v "$PWD/config:/config" \
  -v "$PWD/repo:/repo" \
  ghcr.io/djelibeybi/ol-repo-sync
```

For each `yum` or `uln` source configured in `config/repos.json`, the sync process will:

  1. Enable the repo (`yum`) or subscribe to the channel (`uln`).
  2. Check if there are any new packages available in the repo
  3. Download all new packages
  4. Disable the repo or unsubscribe from the channel

Only one source is synced at a time. To run multiple syncs concurrently, create multiple configurations, each with a _unique_ set of sources.

Ensuring that each sync process has a different set of sources allows you to run them in parallel, all mounting the the same local `$PWD/repo` directory, without worrying about conflicts or file collisions.

Configure regular updates by running the container using either `cron` or a `systemd` timer.

## Accessing the synced repos

A web server is required to make the synced content available to local clients. The `Dockerfile.nginx` and `Dockerfile.httpd` images can be used to create containers running either NGINX or Apache for this purpose.

To use NGINX as the web server, run:

```bash
docker build -t ol-repo-webserver -f Dockerfile.nginx .
```

Or to use Apache as the web server, run:

```bash
docker build -t ol-repo-webserver -f Dockerfile.httpd .
```

> The `ghcr.io/djelibeybi/ol-repo-webserver` image uses NGINX which is the recommended option.

The `repo/` directory is mounted read-only into the `ol-repo-webserver` container. This allows the web server to continue running and serving clients while repo syncs are active.

### Configuring Oracle Linux clients

The default configuration on a fresh install of Oracle Linux uses `yum$ociregion.$ocidomain`
as the host name for each repo provided by Oracle. The values for `$ociregion`
and `$ocidomain` are set via files in `/etc/yum/vars`.

To use these variables to point to your local repo mirror, ensure the host name for
your mirror starts with `yum`. Then, add any host name suffix to `ociregion` and
the domain name (and port) to `/etc/yum/vars/ocidomain`.

For example, if the URL for your mirror is `yum-mirror.example.com:8080`:

```bash
$ echo "-mirror" | tee /etc/yum/vars/ociregion
-mirror
$ echo ".example.com:8080" | tee /etc/yum/vars/ocidomain
.example.com:8080
```

This enables the use of the Oracle Linux release RPMs, e.g. `oracle-epel-release-el8` or `oraclelinux-developer-release-el8` without the need to modify individual files.

## Contributing

This project welcomes contributions from the community. Before submitting a pull
request, please [review our contribution guide](./CONTRIBUTING.md).

## License

Copyright (c) 2020, 2022 Avi Miller.

Released under the Universal Permissive License v1.0 as shown at <https://oss.oracle.com/licenses/upl/>.

[ULN]: https://linux.oracle.com
[YUM]: https://yum.oracle.com
