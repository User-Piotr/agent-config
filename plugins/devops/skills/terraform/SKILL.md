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

Providers talk to Terraform over a Unix socket, which the sandbox blocks. The read commands (`init`, `validate`, `plan`, `fmt`, `providers`, `show`, `output`, `version`, `graph`, `state list`, `state show`) are therefore excluded from the sandbox in settings and allowed without a prompt — but only when the call is that one command:

- `cd` into the directory in one Bash call, then run `terraform validate` in the next; the working directory carries over. `cd dir && terraform validate`, `terraform -chdir=dir …`, pipes, redirects and `$(…)` keep the call sandboxed, and it fails.
- If it still fails with `plugin failed to negotiate the initial go-plugin protocol handshake`, the setup is missing that exclusion: report it, hand the user the command, and name the validation as still open. Do not retry it with the sandbox disabled.

`terraform init` leaves an untracked `.terraform/` directory; mention it rather than committing or deleting it.
