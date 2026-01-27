# TYPO3 Code Review Action

GitHub Action that performs TYPO3 CMS (v11+) code review checks:
- TYPO3 coding standards via PHP_CodeSniffer
- Basic TYPO3 security/deprecation heuristics
- Emits GitHub Actions annotations

## Usage

```yaml
name: TYPO3 Code Review
on:
  pull_request:
  push:
    branches: [ main ]

jobs:
  typo3-review:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: your-org/typo3-code-review-action@v1
        with:
          path: .
          phpcs: true
          security_checks: true
```

## Inputs

| Input | Default | Description |
| --- | --- | --- |
| `path` | `.` | Path to scan. |
| `phpcs` | `true` | Run PHP_CodeSniffer with TYPO3 coding standards. |
| `phpcs_version` | `3.9.0` | PHPCS version to download. |
| `coding_standards_ref` | `main` | TYPO3 coding standards git ref/tag. |
| `phpcs_standard` | `TYPO3CMS` | PHPCS standard name. |
| `fail_on_phpcs` | `false` | Fail when PHPCS errors are found. |
| `security_checks` | `true` | Run basic security heuristics. |
| `exclude` | `vendor,node_modules,.git` | Comma-separated directories to exclude. |
| `debug` | `false` | Enable debug output. |

## Outputs

| Output | Description |
| --- | --- |
| `phpcs_errors` | PHPCS error count. |
| `phpcs_warnings` | PHPCS warning count. |
| `security_critical` | Critical security finding count. |
| `security_warnings` | Security warning count. |
| `security_notices` | Security notice count. |

## Notes

- The action downloads PHP_CodeSniffer and TYPO3 coding standards at runtime.
- The action fails only when critical security findings are detected (or when `fail_on_phpcs` is enabled).
- No Composer install is required in the target repository.

## Maintainer

Landolsi Webdeisgn  
Website: https://landolsi.de  
Impressum: https://landolsi.de/impressum
