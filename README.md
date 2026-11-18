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
The repository requires **Package checks** before merge; a failed update does not affect consumers until a new revision is merged and selected in their lockfile.
Package update PRs are merged manually.
Maintainers can rerun **Checks** on an update branch if its check run is missing.
