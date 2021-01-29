# Oracle Linux ULN and YUM mirror

The `Dockerfile` and scripts in this repo create a container image that is able
to sync content from both the [Unbreakable Linux Network][ULN] and the
[Oracle Linux yum server][YUM] with repo URLs that match those found on
<https://yum.oracle.com>.

It also includes a web server image that can be used to serve the content.

## Building the image

To build the image, clone this repo and run:

```bash
docker build -t container-reposync .
```

## Configuration

Once the image is created you will need to create the required configuration
files on the host.

* Copy [`config/repos.sample.json`](./config/repos.sample.json) to
  `config/repos.json` and add all the repos you want to sync to either the
  `uln` or `yum` array. The `config/repo-map.json` file contains a list of all
  available repos.

> **Note:** some repos are only available via ULN, including all repos that
  contain the word `base`, `patch`,`ksplice`, `JavaSE` and `Exadata`. These repos
  may be further restricted to specific CSIs.

For the best performance while syncing, use the `yum` source instead of `uln`
for all repos that are hosted on <https://yum.oracle.com>.

> **Note:** an Oracle Linux support subscription is required to sync directly
  from ULN. If you do not have a support subscription, remove the `uln`
  array completely from the `config/repos.json` file.

* Copy [`config/uln.sample.conf`](./config/uln.sample.conf) to `config/uln.conf`
  and replace the placeholders with Oracle SSO credentials and an active CSI.
  To protect the content of this file, run `chmod 400 config/uln.conf` to prevent
  anyone except yourself from access.

The sync process requires two volumes to be mounted into the container:

* `/etc/sysconfig/rhn/` stores ULN registration details.
* `/repo` is the base directory into which the repo packages and metadata will
  be synced. The file system hosting `/repo` needs to have lots of available
  disk space.

## (Optional): Registering with ULN

Before content can be synced from ULN, the container has to be registered. The
following command will map the local `rhn/` directory to `/etc/sysconfig/rhn/`
inside the guest and then automatically register the container using the
ULN credentials provided in `config/uln.conf`:

```bash
docker run --rm -it \
  -v ${PWD}/rhn:/etc/sysconfig/rhn \
  -v ${PWD}/config:/config \
  container-reposync register
```

This may take a few minutes and will return to the command prompt when done.
Registration is only required once as long as the `/etc/sysconfig/rhn` volume
is provdided.

## Syncing content

The following command will sync the repos configured in `config/repos.json`
to the volume bound to `/repo`:

```bash
docker run --rm -it \
  -v ${PWD}/rhn:/etc/sysconfig/rhn \
  -v ${PWD}/config:/config \
  -v ${PWD}/repo:/repo \
  container-reposync
```

The container will automatically subscribe and subscribe to each channel
configured in `repos.json` and will create the identical hierarchy to that
used by by `yum.oracle.com`.

This command could be scheduled to run on a recurring schedule via
a `cronjob` or `systemd` timer.

## Serving content to client systems

A web server is required to make the synced content available to local clients.
The `Dockerfile.httpd` is provided to create an Oracle Linux 8 container running
Apache 2.4 for this  purpose.

Build the `httpd-server` server image:

```bash
docker build -t httpd-server -f Dockerfile.httpd .
```

Create and start a container named `yum-server` using the image:

```bash
docker run --detach --name yum-server \
  -p 8080:80 \
  -v ${PWD}/repo:/var/www/html/repo:ro \
  httpd-server
```

Note that the `repo/` directory is bound read-only into the `yum-server`
container. This allows the container to continue running and serving clients
while the repos are updated.

## Contributing

This project welcomes contributions from the community. Before submitting a pull
request, please [review our contribution guide](./CONTRIBUTING.md).

## Security

Please consult the [security guide](./SECURITY.md) for our responsible security
vulnerability disclosure process.

## License

Copyright (c) 2021 Oracle and/or its affiliates.

Released under the Universal Permissive License v1.0 as shown at
<https://oss.oracle.com/licenses/upl/>.

[ULN]: https://linux.oracle.com
[YUM]: https://yum.oracloe.com
