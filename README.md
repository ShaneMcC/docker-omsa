# docker-omsa

Dell OpenManage Server Administrator in Docker.

This was originally loosely based on https://hub.docker.com/r/jdelaros1/openmanage/ but updated for a newer version of OMSA and using the latest AlmaLinux release instead of CentOS, but has since diverged somewhat.

Given that [OMSA is EOL Upstream](https://www.dell.com/support/kbdoc/en-us/000224826/omsa-eol-landing-page) as of Sept 30 2024 (with only security fixes until Sept 30 2027) - this repo is using AlmaLinux 9 which is the newest version that OMSA supports.

Parts of this container may seem a bit icky because it runs `systemd` within the container to get openmanage to start, but it does the job. `omreport`, `dsu` and the open manage web ui all work.

No SNMP support, maybe later.

## Running

This can be ran with something like:

```sh
docker run --privileged -d -p 1311:1311 --restart=always \
    -e OMSA_USER="SomeUsername" -e OMSA_PASS="SomePassword" \
    -v /lib/modules/`uname -r`:/lib/modules/`uname -r` \
    --cgroupns private --name=omsa shanemcc/docker-omsa:latest
```

- Drop the `-p 1311:1311` if the web ui is not desired
- Switch from `latest` to `dev-latest` if you want a more frequently updated container (this gets rebuilt periodically when upstream changes  (checked each night), compared to the less-frequent tagged-images which `latest` tracks.)
- If you use `-e UNCERTIFIED_DRIVES="yes"` then non-dell drives will now show as "Status: OK" rather than "Status: Non-Critical" like they do by default
- `OMSA_USER_FILE` or `OMSA_PASS_FILE` can also be used in place of the non-`_FILE` variants (not both) if you do not want these as an env var (eg you want to use docker secrets.) Only the first line per file is used.

And you can then query things with something like:

```sh
docker exec omsa omreport chassis bios
```

etc.

`dsu` is also available inside the image:

```sh
docker exec -it omsa dsu --inventory
```

For updating, as long as the old container is running we can re-create the container using something like this (adapt this if you changed the example run command):

```sh
OMSA_USER=$(docker exec omsa sh -c 'echo ${OMSA_USER}') \
OMSA_PASS=$(docker exec omsa sh -c 'echo ${OMSA_PASS}') \
sh -c 'if [ -n "${OMSA_USER}" ] && [ -n "${OMSA_PASS}" ]; then
           docker pull shanemcc/docker-omsa:latest && \
           docker stop omsa && \
           docker rm omsa && \
           docker run --privileged -d -p 1311:1311 --restart=always \
               -e OMSA_USER="${OMSA_USER}" -e OMSA_PASS="${OMSA_PASS}" \
               -v /lib/modules/`uname -r`:/lib/modules/`uname -r` \
               --cgroupns private --name=omsa shanemcc/docker-omsa:latest
        fi'
```
This will re-create the container using the same settings previously used for the `OMSA_USER` and `OMSA_PASS` vars.

# Comments, Questions, Bugs, Feature Requests etc.

Bugs and Feature Requests should be raised on the [issue tracker on github](https://github.com/ShaneMcC/docker-omsa/issues), and I'm happy to receive code pull requests via github, however I may not always accept every pull request if it does not meet my vision for the project.

I can be found idling on various different IRC Networks, but the best way to get in touch would be to message "Dataforce" on Quakenet (or chat in #Dataforce), or drop me a mail (email address is in my github profile)
