# Code Review Guidelines

valigatorHealthCheck is a Bash system health-check and diagnostics toolkit for Valigator's Linux validator servers, with an Ansible deployment playbook.

Review ONLY the changes in this pull request: the diff between the base branch
and the pull request head (`git diff origin/<base>...HEAD`). Do not comment on
unchanged code.

Read enough of the repository to review against its real conventions (the
README, any CLAUDE.md, and the files the change touches) before commenting.

## What to look for

- Bugs and logic errors: wrong conditions, unhandled failures, broken paths or
  references, behaviour that does not match the change's evident intent.
- Security: secrets, tokens or keys committed in the diff; command injection or
  unquoted variables in shell; unsafe use of `eval`, `sudo` or `rm`; disabled
  TLS verification; overly broad permissions in workflow files.
- Operational risk: changes that could break a production host, service or
  scheduled job, or remove a safety check.

Do not comment on style, formatting or wording.

## Output format

List each finding on its own line as `Severity: path:line: issue and suggested
fix`, where Severity is Critical, High, Medium or Low. If there are no findings,
reply with the single line `No findings.`
