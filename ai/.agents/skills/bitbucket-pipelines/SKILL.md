---
name: bitbucket-pipelines
description: How to read, change, and debug bitbucket-pipelines.yml and Bitbucket repository or deployment variables safely. Use when a Bitbucket pipeline fails, when editing bitbucket-pipelines.yml, or when a task needs a Bitbucket variable set.
---

# Bitbucket Pipelines

## Reading a failure

- Read the failing step's log yourself before asking me for it. The REST API lists steps at
  `GET /2.0/repositories/{workspace}/{repo_slug}/pipelines/{pipeline_uuid}/steps/` and serves each log at
  `.../steps/{step_uuid}/log`. Ask for a paste or a screenshot only when no read-only credential is available.
- Find the first error, not the last line. A later step usually fails because an earlier step's artifact or variable
  is missing.

## Changing the YAML

- Keep the existing structure (`definitions`, then `pipelines` with `default`, `branches`, `pull-requests`, `tags`,
  and `custom`) and reuse the YAML anchors the file already defines.
- Deploying steps declare their `deployment` environment, and production steps keep `trigger: manual` unless the
  repository already deploys automatically.
- Skip unrelated steps with `condition: changesets: includePaths`, and pass files between steps with `artifacts`
  instead of rebuilding them.
- Prefer OIDC (`oidc: true`) to long-lived cloud keys when the target supports it.
- Check that the file still parses (for example with `yq`) before pushing. There is no official local linter, so the
  first real run is a push to a feature branch.

## Variables and secrets

- Deployment variables apply only to steps with that `deployment`, and override workspace and repository variables
  of the same name.
- Secured variables are masked in logs and cannot be read back through the UI or the API. Never echo them, write
  them to artifacts, or ask for their values in chat.
- When I must set a value, give the exact variable name, its scope (workspace, repository, or deployment
  environment), whether it is secured, and a copy command that reads it from its source of truth, for example
  `gcloud secrets versions access latest --secret=<name> | pbcopy`.
