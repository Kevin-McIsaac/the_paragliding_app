# Security policy

## Supported versions

The latest release on Google Play receives fixes. Older versions do not.

## Report a vulnerability

Use GitHub private vulnerability reporting:
https://github.com/Kevin-McIsaac/the_paragliding_app/security/advisories/new

Do not open a public issue for a security problem.

## Scope

- The app and its local flight data.
- The release workflow and signing keys.
- Third-party API keys and endpoints.

## Secrets

Never commit `env.json`, `upload-keystore*.jks`, `upload-cert*.pem`, or an API key.
The repository ignores these paths. If a secret reaches a commit, rotate it and report
it privately.
