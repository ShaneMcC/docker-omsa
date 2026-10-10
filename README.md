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

## Will it work on my server?

A Dell PowerEdge, and the container has to run **on that server** — OMSA reads the hardware through the host, so unlike an iDRAC client it cannot be pointed at another machine.

Which generations work is decided by the OMSA release in the image rather than by the container:

| PowerEdge generation | OMSA 11.1.0.0 |
| --- | --- |
| 14th, 15th, 16th | what Dell's final release was tested against, and what its support statement covers |
| 13th, and older still | recognised, which is not the same thing as supported — see below |
| 17th | never — OMSA was discontinued before those shipped |

Dell's end of life page says the final release "supports 14th, 15th, and 16th-Generation servers", which reads as a floor and is a ceiling. What OMSA does at run time is a separate question with an actual answer: `srvadmin-omilcore` ships a platform list, `syslist.txt`, and `CheckSystemType` refuses to start the data engine on a system identifier that is not in it. Read out of `srvadmin-omilcore-11.1.0.0-5773.el9.x86_64.rpm`, the exact package this image installs, that file carries the whole 13th generation:

```
0600=PER730   0601=PER630   0602=PET630   0627=PER730XD   060E=PEM630   061B=PEFC630
```

and keeps going back through the 12th and into the 11th (`0235=PER710`, `0236=PER610`, `0237=PET610`). So an R730 or a T630 starts, where a 17th-generation machine would not.

Recognised is not a promise that everything reports, though. Dell withdrew support for those generations rather than the code path, and the half most likely to have quietly rotted is storage — the PERC libraries rather than the BMC.

### Architecture

`linux/amd64` only, and that will not change: every one of the forty packages making up `srvadmin-all` is `x86_64`, there is no source to rebuild from, and OMSA is end-of-life. An arm64 image would be an arm64 base with no OMSA in it.

### What the host has to provide

`--privileged` because OMSA talks to IPMI character devices, to `sysfs`, and to the storage controller through kernel modules it loads itself. `--cgroupns private` because the container runs `systemd` as PID 1, and systemd in a container is sensitive to how the host arranges cgroups.

And the kernel modules, which is what the `/lib/modules` mount is for — the container cannot ship them, because a module has to match the running kernel:

| Module | What it is for |
| --- | --- |
| `dcdbas` | Dell's systems-management base driver — the SMI / SMBIOS interface OMSA and `libsmbios` go through |
| `dell_rbu` | [Remote BIOS Update](https://www.kernel.org/doc/html/latest/admin-guide/dell_rbu.html) — only needed for flashing the BIOS from OMSA |
| `ipmi_si`, `ipmi_devintf`, `ipmi_msghandler` | what creates and drives `/dev/ipmi0` |

A stock Debian, Ubuntu or RHEL-family kernel has all of them. A hypervisor's own kernel may not.

## The web interface

`https://<your host>:1311` — `https`, not `http`.

OMSA generates its own self-signed certificate at install time with the container's hostname as the common name, so a browser objects twice over: self-signed, and named after a container ID rather than the address you typed. Both are expected. It can be regenerated for a name of your choosing:

```sh
docker exec omsa omconfig preferences webserver \
    attribute=gennewcert cn=omsa.example.lan validity=365 webserverrestart=true
```

That is also where the listening port, the bind address, the TLS version, the cipher list and the session timeout live, and `attribute=uploadcert` takes a PKCS#12 bundle if you have a certificate of your own.

Log in with `OMSA_USER` and `OMSA_PASS`. The account is mapped to OMSA's `Administrator` role through `/opt/dell/srvadmin/etc/omarolemap`, which the entrypoint writes at every start.

## Troubleshooting

### `modprobe: FATAL: Module dell_rbu not found`

Your host's kernel was built without it. **On most hosts this is cosmetic**: `dell_rbu` is only used for flashing the BIOS from OMSA, and temperatures, fans, power supplies, storage and the web interface do not go through it.

It is not universally cosmetic. On XCP-ng, whose kernel ships without the module, [OMSA's services have been reported to fail to start outright](https://xcp-ng.org/forum/topic/2499/broken-dell-management-missing-driver), taking 1311 with them. So: if the web interface answers, ignore the line. If it does not, the missing module is a candidate rather than a red herring — most distributions ship it as `CONFIG_DELL_RBU=m`, a `modprobe dell_rbu` away.

`dcdbas` and the `ipmi_*` modules are different: they are what OMSA reads the hardware *through*, so without them it comes up and reports nothing, which is not the same failure as not coming up. If the interface loads and every table is empty, look at the modules. If it does not load at all, they are not the problem.

### Nothing is listening on 1311

In this order:

1. `docker logs omsa` — it may have exited immediately saying which environment variable was missing or wrong.
2. `docker exec omsa /opt/dell/srvadmin/sbin/srvadmin-services.sh status` — the authoritative answer to "did OMSA actually start".
3. `docker exec omsa lsmod | grep -iE 'dell|ipmi|dcdbas'` — if that is empty, the modules never loaded.
4. Whether the container really has `--privileged` and `--cgroupns private`. Without the first, OMSA starts and then fails at the first thing that touches the hardware, which is not always loud.

### `omreport storage` shows nothing, or less than you expect

A controller in HBA or pass-through mode has no virtual disks to report, which is not a fault, and a controller OMSA does not know — a third-party HBA, an NVMe device behind no controller — will not appear at all. `omreport storage controller` is the first thing to check: if the PERC itself is not listed, nothing behind it will be. Drives Dell did not certify need `UNCERTIFIED_DRIVES`.

# Comments, Questions, Bugs, Feature Requests etc.

Bugs and Feature Requests should be raised on the [issue tracker on github](https://github.com/ShaneMcC/docker-omsa/issues), and I'm happy to receive code pull requests via github, however I may not always accept every pull request if it does not meet my vision for the project.

I can be found idling on various different IRC Networks, but the best way to get in touch would be to message "Dataforce" on Quakenet (or chat in #Dataforce), or drop me a mail (email address is in my github profile)
