# The test suite

```sh
./tests/run_tests.sh              # everything
./tests/run_tests.sh -f dash      # only the cases whose name matches
./tests/run_tests.sh --list       # list them without running
```

No Dell hardware, no iDRAC, no Docker daemon, no network, and nothing to install past `bash` and the coreutils a runner already has. It takes about a second.

## What it tests, and what it deliberately does not

It tests **`docker/run.sh`**, which is the only part of this repository that contains decisions. The `Dockerfile` is a list of versions and a package install; whether it produces a working image is answered by building it, which `build-pr.yml` already does on every pull request and which no unit test can usefully stand in for.

So the suite is aimed at one file and at the things in it that can be wrong without anything saying so: a credential the container accepts when it should refuse, an account it fails to create and starts anyway, a flag it writes the wrong way round.

## How it runs a script that writes to `/opt` and execs `/sbin/init`

`run.sh` writes to absolute paths and ends by replacing itself with init. A test run must not touch any of that on the machine it runs on.

Rather than making the script carry a root prefix it would need only for the tests, the harness copies it into a temporary directory and rewrites those paths to point inside it, then puts mocked `getent`, `adduser`, `chpasswd`, `date` and `init` first on `PATH`. **That is the one compromise in here and it is worth naming**: the suite tests the script's logic, not the filesystem layout of the image. Where the image puts things is the `Dockerfile`'s business and the build's to prove.

The mocks are not stubs that always succeed. `getent` and `adduser` honour `--` exactly as the real ones do, because that behaviour is what several cases are about, and each records what it was asked so a case can assert on the call rather than only on what was left behind. `MOCK_ADDUSER_EXIT` and `MOCK_CHPASSWD_EXIT` make either of them refuse.

## Writing a case

Add a `test_<what it asserts>` function to `tests/cases/entrypoint.sh`. The runner finds it, reports it in declaration order, and turns its name into the line you read — there is nothing to register.

```bash
function test_a_password_containing_a_colon_survives() {
  OMSA_USER=alice OMSA_PASS='pa:ss:word' run_entrypoint

  assert_equals "0" "$ENTRYPOINT_STATUS" "exit status"
  assert_equals "alice:pa:ss:word" "$(cat "$MOCK_CHPASSWD_STDIN")" "chpasswd stdin"
}
```

What the harness gives you:

| | |
| --- | --- |
| `run_entrypoint` | runs the script; leaves `ENTRYPOINT_STATUS` and `ENTRYPOINT_OUTPUT` |
| `existing_user NAME` | makes the mocked `getent` find that account |
| `role_map`, `storage_ini` | print the two files the script writes |
| `calls_matching PATTERN` | how many mock invocations matched |
| `MOCK_ADDUSER_EXIT`, `MOCK_CHPASSWD_EXIT` | make a mock refuse |
| `assert_equals`, `assert_contains`, `assert_not_contains`, `assert_file_absent` | each takes a trailing label naming what is being asserted, which is what the failure line reads |

## Three rules the runner enforces rather than trusts

- **Case names are unique across the suite.** Every case file is sourced into one shell, so two cases sharing a name would silently replace one another and the runner would report a pass for a body that never ran. It refuses to start instead.
- **A case that asserts nothing fails.** Passing by doing nothing is worse than failing, because it is silent.
- **Assertions record and carry on.** A case reports every failure it found rather than only the first, which is why each one takes a label. Where the rest of a case cannot run after a failure, write `assert_... || return 1`.

Each case runs in its own subshell with its own sandbox, so one leaking a variable or leaving a file behind cannot reach the next.
