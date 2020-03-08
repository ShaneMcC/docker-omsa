# docker-omsa

Dell OpenManage Server Administrator in Docker.

This is loosely based on https://hub.docker.com/r/jdelaros1/openmanage/ but updated for a newer version of OMSA. (20.02)

Currently this is a bit icky because it runs systemd within the container to get openmanage to start, but it does the job for now.

No SNMP support, maybe later.

## Running

This can be ran with something like:

```sh
docker run --privileged -d -p 1311:1311 --restart=always \
    -e OMSA_USER="SomeUsername" -e OMSA_PASS="SomePassword" \
    -v /lib/modules/`uname -r`:/lib/modules/`uname -r` \
    --name=omsa shanemcc/docker-omsa
```

And you can then query things with something like:

```sh
docker exec omsa omreport chassis bios
``

etc.
