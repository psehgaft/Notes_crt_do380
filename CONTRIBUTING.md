# Contributing

## Exercise format

New exercises must use a two-digit sequence and a descriptive lowercase filename, for example `10-gitops-application-sync.md`.

Use these sections in order:

1. Objectives
2. Prerequisites
3. Scenario
4. Challenge
5. Implementation
6. Validation
7. Troubleshooting
8. Cleanup
9. Review questions

Keep reusable YAML and Ansible content under `templates/`. Use `psehgaft.org` for example DNS names and `<VALUE>` for values that learners must supply. Never commit credentials, tokens, private keys, kubeconfigs, or real customer information.

## Validation

Before proposing a change:

```bash
find templates -type f \( -name '*.yaml' -o -name '*.yml' \) -print
npx --yes markdownlint-cli2 '**/*.md'
```

Apply manifests to a disposable test cluster when the required operators are available. Confirm that cleanup steps remove resources created by the exercise.

