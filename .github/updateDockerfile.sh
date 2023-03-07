#!/bin/bash

# File we're updating
DOCKERFILE="${GITHUB_WORKSPACE}/Dockerfile"

if [ "$(cat "${DOCKERFILE}" | grep "FROM almalinux:")" == "" ]; then
	echo "Primary image changed, please update .github/updateDockerfile.sh"
	exit 1
fi;

# Latest version of our base image
LATEST_IMAGE=$(curl -L -s 'https://registry.hub.docker.com/v2/repositories/library/almalinux/tags' | jq -r '[.results[].name | select(match(".*-minimal-.*"))] | sort | reverse | .[0]')
RHEL_VER="${LATEST_IMAGE%%.*}"
ARCH="x86_64"
OS_REPO=$(curl -s -L "https://linux.dell.com/repo/hardware/dsu/mirrors.cgi?osname=el${RHEL_VER}&basearch=${ARCH}&native=1")
OSI_REPO="https://linux.dell.com/repo/hardware/dsu/os_independent"

LATEST_SRVADMIN=$(curl -s -L "${OS_REPO}/repodata/filelists.xml.gz" | gunzip - | grep -iA1 "package.*srvadmin-all.*${ARCH}" | grep "<version" | awk -F\" '{print "srvadmin-all-" $4 "-" $6}')
LATEST_DSU=$(curl -s -L "${OSI_REPO}/repodata/filelists.xml.gz" | gunzip - | grep -iA1 "package.*dell-system-update.*${ARCH}" | grep "<version" | awk -F\" '{print "dell-system-update-" $4 "-" $6}')

echo "Latest image: ${LATEST_IMAGE}"
echo "Latest srvadmin-all: ${LATEST_SRVADMIN}"
echo "Latest dell-system-update: ${LATEST_DSU}"
if [ "" == "${LATEST_IMAGE}" -o  "" == "${LATEST_SRVADMIN}" -o "" == "${LATEST_DSU}" ]; then
	exit 1
fi;

# Update main image tag
if [ "${LATEST_IMAGE}" != "" ]; then
	sed -ir "s/FROM almalinux:[^ ]+/FROM almalinux:${LATEST_IMAGE}/" ${DOCKERFILE}
fi;

# Update our ADD-ed files
cat Dockerfile | grep "^ADD http" | while read LINE; do
	SPLIT=($LINE)
	HASH=$(curl -L -s ${SPLIT[1]} | md5sum | awk '{print $1}')
	FILE=${SPLIT[2]}
	NEWFILE=${FILE%%-*}-${HASH}

	ESCAPED_FILE=$(printf '%s\n' "$FILE" | sed -e 's/[\/&]/\\&/g')
	ESCAPED_NEWFILE=$(printf '%s\n' "$NEWFILE" | sed -e 's/[\/&]/\\&/g')

	sed -i "s/${ESCAPED_FILE}/${ESCAPED_NEWFILE}/g" ${DOCKERFILE}
done;

# Update `dnf install`` command
sed -ir 's/dnf -y install srvadmin-all[^ ]* dell-system-update[^ ]*/dnf -y install '"${LATEST_SRVADMIN}"' '"${LATEST_DSU}"'/' ${DOCKERFILE}

# Has Changed?
echo ""
git --no-pager diff "${DOCKERFILE}"
git diff-files --quiet "${DOCKERFILE}"
CHANGED=${?}

if [ $CHANGED != 0 ]; then
	echo "Dockerfile was changed"
	echo "changes_detected=true" >> $GITHUB_OUTPUT
else
	echo "changes_detected=false" >> $GITHUB_OUTPUT
fi;
