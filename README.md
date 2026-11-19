# Nix packages

Nix flake for CLI packages built from official upstream distributions.
This repository publishes Nix definitions, not binaries.

| Package | Systems | Upstream metadata |
| --- | --- | --- |
| `antigravity-cli` | Linux x86_64 | Google Antigravity updater manifest |
| `gencode` | Linux x86_64 | npm `@genspark/gencode-linux-x64-baseline` |
| `genspark-cli` | Linux x86_64/aarch64 and macOS aarch64 | npm `@genspark/cli` |
| `herdr-core` | Linux x86_64 and aarch64 | herdr-core release manifest |
| `supabase-cli` | Linux x86_64 | Supabase CLI GitHub releases |

```sh
nix run github:reta-ygs/nix-packages#herdr-core -- --version
```

To use the packages in another flake and share its nixpkgs pin:

```nix
inputs.nix-packages = {
  url = "github:reta-ygs/nix-packages";
  inputs.nixpkgs.follows = "nixpkgs";
};
```

Use `inputs.nix-packages.packages.${system}.herdr-core` or select another package from the table.
Update the `nix-packages` flake lock entry with `nix flake update nix-packages` or Renovate lock file maintenance.

## Updates

The **Update packages** workflow checks each upstream daily and can also be run for a single package.
It verifies the new download against upstream metadata and runs an x86_64 Linux build and install checks before opening a PR.
Genspark CLI updates also regenerate its npm lockfile and Nix dependency hash without running npm install scripts.
The repository requires **Package checks** against the current `main` before merge; a failed update does not affect consumers until a new revision is merged and selected in their lockfile.
Package update PRs are merged manually.
The update workflow explicitly dispatches **Checks** on its branch because pushes made with `GITHUB_TOKEN` do not trigger push workflows.
Maintainers can rerun **Checks** on an update branch if its check run is missing.
If `main` has advanced, first update the branch with the latest `main`, then run **Checks** on the new head; rerunning checks on a stale head is not sufficient.

## Repository security

This is a public, maintainer-operated repository, not an open contribution project.
Pull request creation is restricted to collaborators, and Issues, Discussions, Wiki, and Projects are disabled.
Public read access and forks remain available.

**Checks** runs only on branch pushes within this repository or authorized manual/API dispatches, including trusted update automation, not on pull request events.
Opening or updating a fork pull request does not trigger CI in this repository.
Third-party Actions must be pinned to full commit SHAs.
The `main` branch protection applies to administrators, requires up-to-date **Package checks**, and forbids force pushes and branch deletion.

Human write/admin access is reserved for the repository owner; untrusted contributors must not receive write access.
Any GitHub App or workflow granted write permissions is also trusted automation.
The external-contributor approval policy applies to fork pull request workflows only, not same-repository pushes or manual dispatches.
A repository writer can change branch workflows and request additional token permissions; branch-local actor checks and read-only permission declarations do not isolate an untrusted writer.

Package update preparation has read-only repository access and runs separately from publication.
The publication job has write permissions to create an update branch and PR and dispatch checks, but does not execute the candidate package.
GitHub's combined Actions permission to create and approve PRs remains enabled because automatic PR creation requires it; the workflows do not approve or merge PRs.
Upstream checksums establish artifact integrity, not that an upstream release is harmless.

A collaborators-only interaction limit is also applied as a temporary additional restriction.
GitHub limits its duration to six months; it expires unless renewed.
The PR creation policy and the absence of pull request CI triggers do not depend on that temporary limit.
