# Security policy

OptiEleven runs as administrator and changes system settings, so security reports matter.

## Supported versions

Only the latest release gets fixes. Run `irm optieleven.app | iex` again to update.

## Reporting a problem

Please don't open a public issue. Report it privately on GitHub: **[Security → Report a vulnerability](https://github.com/bila4l4/OptiEleven/security/advisories/new)**.

Include what you found, how to reproduce it, and which version and Windows build you used. You'll get an answer within a few days. Once there's a fix, it ships in a new release and the advisory is published, with credit to you if you want it.

## What counts

For example: a way for a program without admin rights to make OptiEleven change something as administrator, scripts that run without the checks described in the README, or the install command running something other than the published release. A tweak that does what its description says is not a security problem, but tell us in a normal issue if the description is wrong.
