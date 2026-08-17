# Contributing

Keep changes focused on exact TCP bind verification.

1. Use synthetic `ss` fixtures.
2. Do not include customer names, domains, routable IP addresses, logs or screenshots.
3. Never commit `.env`, credentials or private keys.
4. Add or update a deterministic test.
5. Run `make test`.
6. Run `./scripts/prepublish-gate.sh .` before opening a pull request.
7. Explain operational impact and rollback in the pull request.
