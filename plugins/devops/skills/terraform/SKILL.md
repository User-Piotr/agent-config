---
name: terraform
description: Terraform and OpenTofu work. Use before changing, validating or planning a Terraform module, layer, provider or state, or when a plan output needs explaining.
---

# Terraform

The repository's own `AGENTS.md` outranks everything here. Read it first.

## Shape of the work

- Find the existing module or layer the change belongs to and follow its layout, naming and variable conventions before adding a new one. A new resource goes in the file its kind already lives in.
- Follow the provider and module version constraints the repository pins. Do not bump a provider as a side effect.
- A module consumed by other layers is shared: name its consumers and the blast radius in the plan.
- A new module input defaults to the current behaviour (a feature off, `null`, an empty list), so existing callers keep working unchanged. A required input is a breaking change: only when the plan says so, with every caller updated in the same change.
- No secrets in `.tf`, `.tfvars` or state-bound defaults. Reference a secrets manager or inject through the environment.

## Validate, read-only

Run in the changed directory, in this order, and report each result:

```bash
terraform fmt -recursive -check
terraform init -backend=false
terraform validate
terraform plan            # only when credentials and a backend are available
```

Also run `tflint` and `trivy config .` when the repository uses them.

## Live mutation belongs to the user

`terraform apply`, `destroy`, `import`, `taint`, `untaint`, `force-unlock`, `state rm|mv|push|replace-provider` and `workspace delete` change infrastructure or state. Never run them. Hand the user the exact command, with `-chdir` or the directory, and the plan it is meant to realise. `plan`, `state list` and `state show` are reads.

## Under the Bash sandbox

`terraform validate` and `terraform plan` can fail with `plugin failed to negotiate the initial go-plugin protocol handshake`. Report it, hand the command to the user to run outside the sandbox, and do not retry it unsandboxed. Name the validation as still open in the hand-back.

`terraform init` leaves an untracked `.terraform/` directory; mention it rather than committing or deleting it.
