#!/bin/sh

echo "Started at $(date)"

# Either credential may be given as a file instead of as an env var, which keeps
# it out of the container's environment -- where "docker inspect" and
# /proc/<pid>/environ can both read it, and where anything that dumps the
# environment on a crash takes it along. "/run/secrets/<name>" is where compose
# and swarm put a secret, so OMSA_PASS_FILE=/run/secrets/omsa_password needs no
# plumbing beyond naming the secret.
#
# The first line is used, without its newline, which is what a file written by
# "echo" or by "docker secret create" from a here-string looks like. A password
# containing a newline therefore cannot be passed this way; the env var still
# takes anything.
read_credential_file() {
	if [ ! -r "$1" ]; then
		echo "Cannot read $1" >&2
		return 1
	fi
	head -n 1 -- "$1"
}

if [ -n "${OMSA_USER_FILE}" ]; then
	if [ -n "${OMSA_USER}" ]; then
		echo 'Specify either OMSA_USER or OMSA_USER_FILE, not both.' >&2
		exit 1
	fi
	OMSA_USER=$(read_credential_file "${OMSA_USER_FILE}") || exit 1
fi

if [ -n "${OMSA_PASS_FILE}" ]; then
	if [ -n "${OMSA_PASS}" ]; then
		echo 'Specify either OMSA_PASS or OMSA_PASS_FILE, not both.' >&2
		exit 1
	fi
	OMSA_PASS=$(read_credential_file "${OMSA_PASS_FILE}") || exit 1
fi

if [ -z "${OMSA_USER}" ] || [ -z "${OMSA_PASS}" ]; then
	echo 'Please specify OMSA_USER and OMSA_PASS env vars (or OMSA_USER_FILE and OMSA_PASS_FILE).'
	exit 1
fi

# Set login credentials
#
# "--" ends the options: without it a username that begins with "-" is read as
# an option rather than as a name. "getent passwd -x" answers "invalid option
# -- 'x'" and exits 64, not "no such user", so the lookup fails for the wrong
# reason and we go on to create an account that useradd then refuses too.
if ! getent passwd -- "${OMSA_USER}" >/dev/null; then
	echo "Creating user ${OMSA_USER}..."
	if ! adduser -- "${OMSA_USER}"; then
		echo "Failed to create user ${OMSA_USER}." >&2
		exit 1
	fi
fi

# printf rather than echo, because echo has no portable way of being told to
# stop looking for options: a username beginning with "-n" or "-e" is eaten as
# one instead of reaching chpasswd.
echo "Setting login password for ${OMSA_USER}..."
if ! printf '%s:%s\n' "${OMSA_USER}" "${OMSA_PASS}" | chpasswd; then
	echo "Failed to set the password for ${OMSA_USER}." >&2
	exit 1
fi

echo "Allowing ${OMSA_USER} access to openmanage..."
echo "${OMSA_USER}    *       Administrator" > /opt/dell/srvadmin/etc/omarolemap

if [ "${UNCERTIFIED_DRIVES}" = "1" ] || [ "${UNCERTIFIED_DRIVES}" = "yes" ]; then
	echo "Allow non-certified drives..."
	sed -i 's/^NonDellCertifiedFlag=.*$/NonDellCertifiedFlag=no/' /opt/dell/srvadmin/etc/srvadmin-storage/stsvc.ini
else
	# Reset to default.
	sed -i 's/^NonDellCertifiedFlag=.*$/NonDellCertifiedFlag=yes/' /opt/dell/srvadmin/etc/srvadmin-storage/stsvc.ini
fi

echo "Clearing old tmp files..."
rm -Rf /tmp/* /var/tmp/*

echo "Starting init..."
exec /sbin/init
