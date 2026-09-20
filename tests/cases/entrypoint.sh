#!/bin/bash
#
# docker/run.sh. One case per behaviour, named for what it asserts -- the
# runner turns the function name into the line it reports, so the name is the
# documentation.

# --------------------------------------------------------- required variables

function test_it_refuses_to_start_with_no_credentials() {
  run_entrypoint
  assert_equals "1" "$ENTRYPOINT_STATUS" "exit status"
  assert_contains "Please specify" "$ENTRYPOINT_OUTPUT" "message"
  assert_not_contains "INIT REACHED" "$ENTRYPOINT_OUTPUT" "init"
}

function test_it_refuses_to_start_with_a_user_and_no_password() {
  OMSA_USER=alice run_entrypoint
  assert_equals "1" "$ENTRYPOINT_STATUS" "exit status"
  assert_not_contains "INIT REACHED" "$ENTRYPOINT_OUTPUT" "init"
}

function test_it_refuses_to_start_with_a_password_and_no_user() {
  OMSA_PASS=secret run_entrypoint
  assert_equals "1" "$ENTRYPOINT_STATUS" "exit status"
  assert_not_contains "INIT REACHED" "$ENTRYPOINT_OUTPUT" "init"
}

function test_an_empty_password_is_not_a_password() {
  OMSA_USER=alice OMSA_PASS="" run_entrypoint
  assert_equals "1" "$ENTRYPOINT_STATUS" "exit status"
}

# ------------------------------------------------------------- the happy path

function test_it_reaches_init_with_both_credentials() {
  OMSA_USER=alice OMSA_PASS=secret run_entrypoint
  assert_equals "0" "$ENTRYPOINT_STATUS" "exit status"
  assert_contains "INIT REACHED" "$ENTRYPOINT_OUTPUT" "init"
}

function test_it_creates_the_account_it_was_given() {
  OMSA_USER=alice OMSA_PASS=secret run_entrypoint
  assert_equals "1" "$(calls_matching '^adduser')" "adduser calls"
  assert_contains "alice" "$(cat "$MOCK_EXISTING_USERS")" "passwd"
}

function test_it_sets_the_password_through_chpasswd() {
  OMSA_USER=alice OMSA_PASS=secret run_entrypoint
  assert_equals "alice:secret" "$(cat "$MOCK_CHPASSWD_STDIN")" "chpasswd stdin"
}

function test_it_grants_the_account_the_administrator_role() {
  OMSA_USER=alice OMSA_PASS=secret run_entrypoint
  assert_contains "alice" "$(role_map)" "omarolemap"
  assert_contains "Administrator" "$(role_map)" "omarolemap"
}

# A password with a colon in it is the case people hit and nobody tests.
# chpasswd splits on the FIRST colon, so it survives -- but only as long as
# nothing upstream of it tries to be clever about the separator.
function test_a_password_containing_a_colon_survives() {
  OMSA_USER=alice OMSA_PASS='pa:ss:word' run_entrypoint
  assert_equals "0" "$ENTRYPOINT_STATUS" "exit status"
  assert_equals "alice:pa:ss:word" "$(cat "$MOCK_CHPASSWD_STDIN")" "chpasswd stdin"
}

# ------------------------------------------------------- an account that exists

function test_an_existing_account_is_not_created_again() {
  existing_user alice
  OMSA_USER=alice OMSA_PASS=secret run_entrypoint
  assert_equals "0" "$(calls_matching '^adduser')" "adduser calls"
  assert_equals "0" "$ENTRYPOINT_STATUS" "exit status"
}

function test_an_existing_account_still_has_its_password_set()
{
  existing_user alice
  OMSA_USER=alice OMSA_PASS=secret run_entrypoint
  assert_equals "alice:secret" "$(cat "$MOCK_CHPASSWD_STDIN")" "chpasswd stdin"
}

# ------------------------------------------------ failures must stop the start
#
# The point of the suite. Before these were checked, either failure left the
# container running with no usable login and an exit status of 0.

function test_a_refused_account_creation_stops_the_container() {
  MOCK_ADDUSER_EXIT=1
  OMSA_USER=alice OMSA_PASS=secret run_entrypoint
  assert_equals "1" "$ENTRYPOINT_STATUS" "exit status"
  assert_not_contains "INIT REACHED" "$ENTRYPOINT_OUTPUT" "init"
  assert_file_absent "$SANDBOX/opt/dell/srvadmin/etc/omarolemap" "omarolemap"
}

function test_a_refused_password_change_stops_the_container() {
  MOCK_CHPASSWD_EXIT=1
  OMSA_USER=alice OMSA_PASS=secret run_entrypoint
  assert_equals "1" "$ENTRYPOINT_STATUS" "exit status"
  assert_not_contains "INIT REACHED" "$ENTRYPOINT_OUTPUT" "init"
  assert_file_absent "$SANDBOX/opt/dell/srvadmin/etc/omarolemap" "omarolemap"
}

function test_it_reports_a_failure_before_exiting() {
  # The wording is deliberately not asserted. What matters is that the last
  # thing the container says is that something failed and which half it was in
  # -- not the exact sentence, which is free to be rephrased.
  MOCK_ADDUSER_EXIT=1
  OMSA_USER=alice OMSA_PASS=secret run_entrypoint
  assert_contains "ailed" "$ENTRYPOINT_OUTPUT" "message"
  assert_contains "user" "$ENTRYPOINT_OUTPUT" "message names the step"

  MOCK_ADDUSER_EXIT=0 MOCK_CHPASSWD_EXIT=1
  OMSA_USER=alice OMSA_PASS=secret run_entrypoint
  assert_contains "ailed" "$ENTRYPOINT_OUTPUT" "message"
  assert_contains "password" "$ENTRYPOINT_OUTPUT" "message names the step"
}

# ------------------------------------------------- names that look like options
#
# A leading dash is where a username stops being data and starts being an
# argument. What the entrypoint does about it is its own business -- refuse the
# name outright, or pass it after an end-of-options marker and let useradd
# refuse it -- so what is asserted here is the outcome both reach: the container
# stops, and nothing was misread as an option on the way.

function test_a_username_starting_with_a_dash_is_refused() {
  OMSA_USER=-x OMSA_PASS=secret run_entrypoint
  assert_equals "1" "$ENTRYPOINT_STATUS" "exit status"
  assert_not_contains "INIT REACHED" "$ENTRYPOINT_OUTPUT" "init"
  assert_not_contains "invalid option" "$ENTRYPOINT_OUTPUT" "output"
}

# ---------------------------------------------- credentials read from a file

function test_both_credentials_can_come_from_files() {
  local USER_FILE PASS_FILE
  USER_FILE="$(secret_file user 'alice')"
  PASS_FILE="$(secret_file pass 'secret')"
  OMSA_USER_FILE="$USER_FILE" OMSA_PASS_FILE="$PASS_FILE" run_entrypoint

  assert_equals "0" "$ENTRYPOINT_STATUS" "exit status"
  assert_equals "alice:secret" "$(cat "$MOCK_CHPASSWD_STDIN")" "chpasswd stdin"
}

# The trailing newline "echo" and "docker secret create" leave behind must not
# become part of the credential.
function test_a_trailing_newline_is_not_part_of_the_credential() {
  local PASS_FILE
  PASS_FILE="$(secret_file pass 'secret
')"
  OMSA_USER=alice OMSA_PASS_FILE="$PASS_FILE" run_entrypoint
  assert_equals "alice:secret" "$(cat "$MOCK_CHPASSWD_STDIN")" "chpasswd stdin"
}

# One of the two has to win, and a container whose credentials depend on which
# is the failure this refuses rather than resolves.
function test_setting_both_a_variable_and_its_file_is_refused() {
  local USER_FILE
  USER_FILE="$(secret_file user 'alice')"
  OMSA_USER=bob OMSA_USER_FILE="$USER_FILE" OMSA_PASS=secret run_entrypoint
  assert_equals "1" "$ENTRYPOINT_STATUS" "exit status"
  assert_not_contains "INIT REACHED" "$ENTRYPOINT_OUTPUT" "init"
}

function test_an_unreadable_credential_file_is_refused() {
  OMSA_USER_FILE="$SANDBOX/not-here" OMSA_PASS=secret run_entrypoint
  assert_equals "1" "$ENTRYPOINT_STATUS" "exit status"
  assert_not_contains "INIT REACHED" "$ENTRYPOINT_OUTPUT" "init"
}

# An empty file is the shape a secret takes when it was created wrong, and it
# must not become an empty password on an account that then exists.
function test_an_empty_credential_file_is_refused() {
  local PASS_FILE
  PASS_FILE="$(secret_file pass '')"
  OMSA_USER=alice OMSA_PASS_FILE="$PASS_FILE" run_entrypoint
  assert_equals "1" "$ENTRYPOINT_STATUS" "exit status"
  assert_not_contains "INIT REACHED" "$ENTRYPOINT_OUTPUT" "init"
}

function test_a_directory_given_as_a_credential_file_is_refused() {
  mkdir -p "$SANDBOX/a-directory"
  OMSA_USER_FILE="$SANDBOX/a-directory" OMSA_PASS=secret run_entrypoint
  assert_equals "1" "$ENTRYPOINT_STATUS" "exit status"
  assert_not_contains "INIT REACHED" "$ENTRYPOINT_OUTPUT" "init"
}

# The name check has to happen after the file is read, or a file is a way round
# it.
function test_a_username_from_a_file_is_validated_too() {
  local USER_FILE
  USER_FILE="$(secret_file user '-x')"
  OMSA_USER_FILE="$USER_FILE" OMSA_PASS=secret run_entrypoint
  assert_equals "1" "$ENTRYPOINT_STATUS" "exit status"
  assert_not_contains "INIT REACHED" "$ENTRYPOINT_OUTPUT" "init"
}

# ------------------------------------------------------- uncertified drives

function test_uncertified_drives_are_refused_by_default() {
  OMSA_USER=alice OMSA_PASS=secret run_entrypoint
  assert_contains "NonDellCertifiedFlag=yes" "$(storage_ini)" "stsvc.ini"
}

function test_uncertified_drives_are_allowed_when_asked_with_one() {
  UNCERTIFIED_DRIVES=1 OMSA_USER=alice OMSA_PASS=secret run_entrypoint
  assert_contains "NonDellCertifiedFlag=no" "$(storage_ini)" "stsvc.ini"
}

function test_uncertified_drives_are_allowed_when_asked_with_yes() {
  UNCERTIFIED_DRIVES=yes OMSA_USER=alice OMSA_PASS=secret run_entrypoint
  assert_contains "NonDellCertifiedFlag=no" "$(storage_ini)" "stsvc.ini"
}

# Anything that is not 1 or yes resets the flag rather than leaving whatever a
# previous run left behind, which is what makes the container's state a
# function of its environment and not of its history.
function test_an_unrecognised_uncertified_drives_value_resets_the_flag() {
  printf 'NonDellCertifiedFlag=no\n' \
    > "$SANDBOX/opt/dell/srvadmin/etc/srvadmin-storage/stsvc.ini"
  UNCERTIFIED_DRIVES=true OMSA_USER=alice OMSA_PASS=secret run_entrypoint
  assert_contains "NonDellCertifiedFlag=yes" "$(storage_ini)" "stsvc.ini"
}
