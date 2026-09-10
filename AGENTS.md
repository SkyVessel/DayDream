# DayDream Agent Notes

## GitHub CLI and the Codex proxy

Codex background commands may inherit a proxy that breaks GitHub API requests even when the user's GitHub CLI login is valid.

### Symptoms

```text
gh auth status
X Failed to log in to github.com account SkyVessel (keyring)
The token in keyring is invalid.

Post "https://api.github.com/graphql": unexpected EOF
Post "https://github.com/login/device/code": unexpected EOF
```

The same account can be authenticated and usable from the user's regular terminal. This is a proxy connection failure, not an expired GitHub token.

### Reproduce

Run a GitHub API command from the Codex command environment while it inherits the proxy at `43.250.91.11:443`:

```bash
gh api user
```

The request may fail with `unexpected EOF`, and `gh auth status` can misleadingly call the Keychain token invalid.

### Resolution

For every GitHub CLI or GitHub API command run by an agent, bypass the inherited proxy for GitHub:

```bash
env -u HTTP_PROXY -u HTTPS_PROXY -u ALL_PROXY \
  -u http_proxy -u https_proxy -u all_proxy \
  NO_PROXY=github.com,api.github.com,uploads.github.com \
  no_proxy=github.com,api.github.com,uploads.github.com \
  gh api user
```

Use the same `env` prefix for `gh release create`, `gh release upload`, and other `gh` operations. Do not log the token, inspect Keychain secrets, or ask the user to re-authenticate before trying this bypass.
