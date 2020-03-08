# Use CentOS 7 base image from Docker Hub
FROM centos:centos7
MAINTAINER Shane Mc Cormack <dataforce@dataforce.org.uk>

# Environment variables
ENV PATH $PATH:/opt/dell/srvadmin/bin:/opt/dell/srvadmin/sbin

# Do overall update and install missing packages needed for OpenManage
RUN yum -y update && \
    yum -y install gcc wget perl passwd which tar libstdc++.so.6 compat-libstdc++-33.i686 glibc.i686

# Add OMSA repo. Let's use this DSU version with a known stable OMSA.
# RUN wget -q -O - http://linux.dell.com/repo/hardware/DSU_16.02.00/bootstrap.cgi | bash
RUN wget -q -O - http://linux.dell.com/repo/hardware/DSU_20.02.00/bootstrap.cgi | bash

# Let's "install all", however we can select specific components instead
RUN yum -y install srvadmin-all && yum clean all

# Prevent daemon helper scripts from making systemd calls
ENV SYSTEMCTL_SKIP_REDIRECT=1

COPY ./docker/run.sh /run.sh

# Run the application
CMD /run.sh
