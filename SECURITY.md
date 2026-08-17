# Security policy

## Reporting

Do not open a public issue containing credentials, personal data, private addresses or customer information. Use the private contact method listed in the maintainer profile.

Include the affected version, a minimal reproduction using synthetic `ss` output and the expected impact. Remove tokens, domains, routable IP addresses and logs that can identify a real environment.

## Supported versions

Only the latest release receives security fixes unless a release note states otherwise.

## Security boundary

`check-bind` reads local listener metadata. It does not modify services, network rules or firewall state. Snapshot files are parsed as text and never executed.

## Secret exposure

If a real credential is committed, removing the line is not sufficient. Revoke or rotate it first, then rebuild the public history from a clean export.
