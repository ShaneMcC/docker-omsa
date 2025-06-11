#!/bin/bash

# File we're updating
DOCKERFILE="${GITHUB_WORKSPACE}/Dockerfile"

if [ "" = "${GITHUB_WORKSPACE}" ]; then
	SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
	DOCKERFILE="${SCRIPT_DIR}/../Dockerfile"
fi;

if [ "" = "${GITHUB_STEP_SUMMARY}" -o "" = "${GITHUB_OUTPUT}" ]; then
	GITHUB_STEP_SUMMARY="/dev/null"
	GITHUB_OUTPUT="/dev/stdout"
fi;

if [ ! -e "${DOCKERFILE}" ]; then
	echo "Dockerfile not found: ${DOCKERFILE}"
	exit 1
fi;

# Current Versions
UPSTREAM="almalinux"
CURRENT_IMAGE=$(cat "${DOCKERFILE}" | grep -Eo "^FROM ${UPSTREAM}:([^ ]+)" | awk -F: '{print $2}')
CURRENT_SRVADMIN=$(cat "${DOCKERFILE}" | grep -Eo "srvadmin-all[^ ]*")
CURRENT_DSU=$(cat "${DOCKERFILE}" | grep -Eo "dell-system-update[^ ]*")

if [ "" == "${CURRENT_IMAGE}" ]; then
	echo "Primary image changed, please update .github/updateDockerfile.sh"
	exit 1
fi;

CHANGED_THING=()

# Latest version of our base image
LATEST_IMAGE=$(curl -L -s 'https://registry.hub.docker.com/v2/repositories/library/'"${UPSTREAM}"'/tags' | jq -r '[.results[].name | select(match(".*-minimal-.*"))] | sort | reverse | .[0]')
RHEL_VER="${LATEST_IMAGE%%.*}"
ARCH="x86_64"
OS_REPO=$(curl -s -L "https://linux.dell.com/repo/hardware/dsu/mirrors.cgi?osname=el${RHEL_VER}&basearch=${ARCH}&native=1")
OSI_REPO="https://linux.dell.com/repo/hardware/dsu/os_independent"
LATEST_SRVADMIN=$(curl -s -L "${OS_REPO}/repodata/filelists.xml.gz" | gunzip - | grep -iA1 "package.*srvadmin-all.*${ARCH}" | grep "<version" | awk -F\" '{print "srvadmin-all-" $4 "-" $6}')
LATEST_DSU=$(curl -s -L "${OSI_REPO}/repodata/filelists.xml.gz" | gunzip - | grep -iA1 "package.*dell-system-update.*${ARCH}" | grep "<version" | awk -F\" '{print "dell-system-update-" $4 "-" $6}')

if [ "${CURRENT_IMAGE}" != "${LATEST_IMAGE}" ]; then
	CHANGED_THING+=(\`"${UPSTREAM}:${CURRENT_IMAGE}\` => \`${UPSTREAM}:${LATEST_IMAGE}\`")
fi;

if [ "${CURRENT_SRVADMIN}" != "${LATEST_SRVADMIN}" ]; then
	CHANGED_THING+=("\`${CURRENT_SRVADMIN}\` => \`${LATEST_SRVADMIN}\`")
fi;

if [ "${CURRENT_DSU}" != "${LATEST_DSU}" ]; then
	CHANGED_THING+=("\`${CURRENT_DSU}\` => \`${LATEST_DSU}\`")
fi;

if [ "" == "${LATEST_IMAGE}" -o  "" == "${LATEST_SRVADMIN}" -o "" == "${LATEST_DSU}" ]; then
	echo "Unable to find new versions."
	exit 1
fi;

# Update main image tag
if [ "${LATEST_IMAGE}" != "" ]; then
	sed -ri "s/FROM ${UPSTREAM}:[^ ]+/FROM ${UPSTREAM}:${LATEST_IMAGE}/" ${DOCKERFILE}
fi;

# Update our ADD-ed files
while read LINE; do
	SPLIT=($LINE)
	HASH=$(curl -L -s ${SPLIT[1]} | md5sum | awk '{print $1}')
	FILE=${SPLIT[2]}
	NEWFILE=${FILE%%-*}-${HASH}

	ESCAPED_FILE=$(printf '%s\n' "$FILE" | sed -e 's/[\/&]/\\&/g')
	ESCAPED_NEWFILE=$(printf '%s\n' "$NEWFILE" | sed -e 's/[\/&]/\\&/g')

	sed -i "s/${ESCAPED_FILE}/${ESCAPED_NEWFILE}/g" ${DOCKERFILE}

	if [ "${FILE}" != "${NEWFILE}" ]; then
		CHANGED_THING+=("\`${FILE}\` => \`${NEWFILE}\`")
	fi;
done < <(cat "${DOCKERFILE}" | grep "^ADD http")

# Update `dnf install`` command
sed -ir 's/dnf -y install srvadmin-all[^ ]* dell-system-update[^ ]*/dnf -y install '"${LATEST_SRVADMIN}"' '"${LATEST_DSU}"'/' ${DOCKERFILE}

# Has Changed?
echo ""
git --no-pager diff "${DOCKERFILE}"
git diff-files --quiet "${DOCKERFILE}"
CHANGED=${?}

if [ $CHANGED != 0 ]; then
	echo "**\`Dockerfile\` was changed**" | tee -a $GITHUB_STEP_SUMMARY

	echo "" | tee -a $GITHUB_STEP_SUMMARY
	for THING in "${CHANGED_THING[@]}"; do
	     echo " - " $THING | tee -a $GITHUB_STEP_SUMMARY
	done
	ALL_CHANGED_THINGS=$(printf ", %s" "${CHANGED_THING[@]}")
	ALL_CHANGED_THINGS=${ALL_CHANGED_THINGS:2}

	echo "changes_detected=true" >> $GITHUB_OUTPUT
	echo "changed_items=${ALL_CHANGED_THINGS}" >> $GITHUB_OUTPUT
else
	echo "No changes detected" | tee -a $GITHUB_STEP_SUMMARY
	echo "changes_detected=false" >> $GITHUB_OUTPUT
	echo "changed_items=" >> $GITHUB_OUTPUT
fi;
