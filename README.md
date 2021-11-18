# Oracle Linux ULN & YUM Repo Mirror

The `Dockerfile` and scripts in this repo create a container image that is able
to sync content from both the [Unbreakable Linux Network][ULN] and the
[Oracle Linux yum server][YUM] with repo URLs that match those found on
<https://yum.oracle.com>.

It also includes a web server image that can be used to serve the content.

## Building the image (optional)

To build the image, clone this repo and run:

```bash
docker build -t ol-repo-sync .
```

Or prefix the image name in the example commands below with `ghcr.io/djelibeybi`
to use the already built binary versions, which are available for both Intel (`x86_64`)
and Arm (`aarch64`) architectures.

## Requirements and configuration

An Oracle Linux support subscription is **required** to sync
from ULN. If you do not have a support subscription, remove the `uln`
array completely from the `config/repos.json` file.
Note that some repos are only available via ULN, including repos that
contain the word `patch`,`ksplice`, `JavaSE` and `Exadata`.

For the best sync performance, use the `yum` source instead of `uln` wherever
possible, as yum.oracle.com leverages the Akamai CDN and will almost always have
much higher download speeds than ULN.

1. (Optional) if you do have an active Oracle Linux support subscription:

    Copy [`config/uln.sample.conf`](./config/uln.sample.conf) to `config/uln.conf`
    and replace the placeholders with Oracle SSO credentials and an active CSI.
    To protect the content of this file, run `chmod 400 config/uln.conf` to prevent anyone except yourself from access.

2. Create a `config/repo-map.json` file by running the following command:

  ```bash
  docker run --rm -it \
    --name ol-repo-sync \
    -v ${PWD}/config:/config \
    ol-repo-sync update
  ```

  This command can be run again at any time if you want to update the
  `config/repo-map.json` file with the latest repo configuration.
  The command should at least be run whenever a new update or major
  version is released so that the new repos are available for syncing.

3. Copy [`config/repos.sample.json`](./config/repos.sample.json) to
  `config/repos.json` and add all the repos you want to sync to either the
  `uln` or `yum` array.

### (Optional) Register with  ULN

4. Before content can be synced from ULN, the container has to be registered. The
   following command will map the local `rhn/` directory to `/etc/sysconfig/rhn/`
   inside the guest and then automatically register the container using the
   ULN credentials provided in `config/uln.conf`:

    ```bash
    docker run --rm -it \
      -v ${PWD}/rhn:/etc/sysconfig/rhn \
      -v ${PWD}/config:/config \
      ol-repo-sync register
    ```

    This will take a few minutes with no output to the terminal but should return to
    the command prompt when completed. Registration is only required to be performed
    once as long as the same volume is mounted to `/etc/sysconfig/rhn` whenever the
    container is launched.

    > **Note:** Source packages are not synced by default. To include source packages,
    > set the `SYNC_SRC` environment variable to `1` by passing `-e SYNC_SRC=1` as
    > an argument to `docker run`.

    If you don't want to build your own image locally, replace `ol-repo-sync` with
    `ghcr.io/djelibeybi/ol-repo-sync` in all the following examples to use the
    [djelibeybi/ol-repo-sync][sync-image] image published to GitHub Container Registry.

## Syncing repo content

5. The following command will sync the repos configured in `config/repos.json`
    to the volume mounted at `/repo` inside the container. In this example, it is being mapped to the `./repo` directory.

    ```bash
    docker run --rm -it \
      -v ${PWD}/rhn:/etc/sysconfig/rhn \
      -v ${PWD}/config:/config \
      -v ${PWD}/repo:/repo \
      ol-repo-sync
    ```

    The container will iterate through each configured repo from yum.oracle.com and
    ULN. It will automatically subscribe to each ULN channel
    configured in `repos.json` and will create the same file structure as
    used by by `yum.oracle.com`. It will also unsubscribe after each repo is
    processed which should avoid most dependency conflicts.

    This command should be scheduled to run on a regular schedule via
    a `cronjob` or `systemd` timer.

## (Optional) Deploy a web server to publish the repos

6. A web server is required to make the synced content available to local clients.
   The `Dockerfile.nginx` is provided to create an Oracle Linux 8 container running
   NGINX 1.20 for this  purpose.

   ```bash
   docker build -t ol-repo-web -f Dockerfile.nginx .
   ```

7. Create and start a container named `ol-repo-webserver` using the image built
   locally. You can replace `ol-repo-webserver` with `ghcr.io/djelibeybi/
   ol-repo-webserver` to use the imag published on GitHub Container Registry:

    ```bash
    docker run --detach
      --name ol-repo-web \
      -p 8080:80 \
      -v ${PWD}/repo:/var/www/html/repo:ro \
      ol-repo-web
    ```

    Note that the `repo/` directory is bound read-only into the `ol-repo-web`
    container. This allows the container to continue running and serving clients
    while the repos are updated.

## Contributing

This project welcomes contributions from the community. Before submitting a pull
request, please [review our contribution guide](./CONTRIBUTING.md).

## License

Copyright (c) 2020, 2022 Avi Miller.

Released under the Universal Permissive License v1.0 as shown at
<https://oss.oracle.com/licenses/upl/>.

[ULN]: https://linux.oracle.com
[YUM]: https://yum.oracle.com
[sync-image]:
[web-image]:
