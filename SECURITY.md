# Security policy

## Supported versions

Fixes land on the latest minor release only.

| Version | Supported |
|---|---|
| 0.1.x | Yes |
| Older | No |

## Reporting a vulnerability

`imaji_store_preflight` reads project files such as `Info.plist`, privacy
manifests and `AndroidManifest.xml`, often in CI. A crafted project file that
makes it hang, crash in an exploitable way, read outside the project, or
write somewhere unexpected is a security problem.

Please report privately: open this repository's **Security** tab and choose
**Report a vulnerability**. This creates a private advisory that only you and
the maintainer can see.

Do **not** open a public issue, pull request or discussion for a
vulnerability.

Useful things to include:

- the package version, `dart --version` and the host OS
- the exact command you ran
- a minimal project or file that reproduces it (invented, never a real
  app's configuration)
- what an attacker could achieve, and any fix you have in mind

## What to expect

You will usually get a first reply within a week. Once the issue is
confirmed, a fix is prepared in the private advisory, released, and the
advisory is published with credit to you unless you prefer otherwise.
