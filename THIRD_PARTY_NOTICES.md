# Third-party notices

SandboxExplorer is an independent reimplementation. It contains no copied
source files from the projects below, but its sandbox-extension technique,
container-enumeration approach and product design are derived from them.
All of them are GPL-3.0-or-later; this project is distributed under the same
license (see `LICENSE`).

## worse_query — Taj C (forcequitOS)

- Repository: https://github.com/forcequitOS/worse_query
- License: GNU GPL version 3 or later
- Contribution: the `Library/Caches` symlink swap + `container_query_create` /
  `container_query_set_class(7)` / `container_query_operation_set_part(3)` /
  `container_query_operation_set_flags` / `container_copy_sandbox_token` /
  `sandbox_extension_consume` chain that issues a sandbox extension for an
  arbitrary existing path, plus the `fsgetpath` object-id enumeration.
- Reimplemented in: `Sources/WQBridge.m`, `Sources/WQPathLeak.m`

## WQManager — hseons

- Repository: https://github.com/hseons/WQManager
- License: GNU GPL version 3 or later
- Contribution: product shape (app container list, per-container file
  browsing, backup/cleanup ideas), App Group discovery via
  `SecTaskCopyValueForEntitlement`, bounded LRU grant cache, dual query-flag
  fallback, token-open verification, and path-safety conventions.
- Reimplemented in: `Sources/WQBridge.m`, `Sources/WQFileOps.m`, `Sources/*.m` (UI)

## WQFiles — kolbicz

- Repository: https://github.com/kolbicz/WQFiles
- License: GNU GPL version 3 or later
- Contribution: reference for container access, container enumeration and
  Launch Services display-name lookup (referenced indirectly through WQManager).

## KAMUI (kamui-escape) — murk-sus

- Repository: https://github.com/murk-sus/kamui-escape
- License: see upstream repository
- Contribution: design reference for `fsgetpath`-based container enumeration.

## Apple frameworks

UIKit, Foundation, Security (`SecTask*` via `dlopen`/`dlsym`), libXPC
(`xpc_string_create`), libsystem (`sandbox_extension_consume` / `release`) and
libsystem_containermanager (`container_query_*`, `container_copy_sandbox_token`)
are used through public headers and guarded runtime symbol lookups. No private
framework is linked at build time.

## License obligations

Any distributed fork or derivative binary must:

1. remain licensed under GPL-3.0-or-later,
2. ship the full license text (`LICENSE`),
3. keep this notices file and the in-app credits panel (`工具 → 技术与上游声明`),
4. make the corresponding complete source available to every recipient of the
   IPA.
