# docker-omsa

Dell OpenManage Server Administrator in Docker.

This was originally loosely based on https://hub.docker.com/r/jdelaros1/openmanage/ but updated for a newer version of OMSA and using the latest AlmaLinux release instead of CentOS, but has since diverged somewhat.

This may seem a bit icky because it runs `systemd` within the container to get openmanage to start, but it does the job.

No SNMP support, maybe later.

## Running

This can be ran with something like:

```sh
docker run --privileged -d -p 1311:1311 --restart=always \
    -e OMSA_USER="SomeUsername" -e OMSA_PASS="SomePassword" \
    -v /lib/modules/`uname -r`:/lib/modules/`uname -r` \
    --cgroupns private --name=omsa shanemcc/docker-omsa
```

And you can then query things with something like:

```sh
docker exec omsa omreport chassis bios
```

etc.

`dsu` is also available inside the image:

```sh
docker exec -it omsa dsu --inventory
```

For updating, as long as the old container is running we can re-create the container using something like this:

```sh
OMSA_USER=$(docker exec omsa sh -c 'echo ${OMSA_USER}') \
OMSA_PASS=$(docker exec omsa sh -c 'echo ${OMSA_PASS}') \
sh -c 'if [ "" != "${OMSA_USER}" -a "" != "${OMSA_PASS}" ]; then
           docker pull shanemcc/docker-omsa && \
           docker stop omsa && \
           docker rm omsa && \
           docker run --privileged -d -p 1311:1311 --restart=always \
               -e OMSA_USER="${OMSA_USER}" -e OMSA_PASS="${OMSA_PASS}" \
               -v /lib/modules/`uname -r`:/lib/modules/`uname -r` \
               --cgroupns private --name=omsa shanemcc/docker-omsa
        fi'
```
This will re-create the container using the same settings previously used for the `OMSA_USER` and `OMSA_PASS` vars.

# Comments, Questions, Bugs, Feature Requests etc.

Bugs and Feature Requests should be raised on the [issue tracker on github](https://github.com/ShaneMcC/docker-omsa/issues), and I'm happy to recieve code pull requests via github, however I may not always accept every pull request if it does not meet my vision for the project.

I can be found idling on various different IRC Networks, but the best way to get in touch would be to message "Dataforce" on Quakenet (or chat in #Dataforce), or drop me a mail (email address is in my github profile)
