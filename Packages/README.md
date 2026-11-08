# Velora local packages (D02 scaffold)

Thin SwiftPM packages mirrored from `Velora/` for future extraction. The app target still compiles sources from `Velora/` via XcodeGen until these packages are wired in `project.yml`.

| Package | Role |
|---------|------|
| **VeloraCore** | Config, API envelope, networking protocol |
| **VeloraDesignSystem** | Design tokens & shared UI (placeholder) |
| **VeloraTestSupport** | Shared test helpers (placeholder) |

```bash
# Validate package manifests (optional)
swift package describe --type json --package-path Packages/VeloraCore
```
