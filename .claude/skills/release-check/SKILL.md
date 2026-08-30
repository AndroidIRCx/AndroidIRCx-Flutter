---
name: release-check
description: Pre-release checklist for AndroidIRCX Flutter — update dependencies, verify analyze/tests, bump the version, then push, PR to main, and tag. Use before every release/tag or when the user asks to prepare, check, or ship a new version.
---

# AndroidIRCX release check

Run every step in order. Stop and report if any step fails — never tag a
version with a red step.

## 1. Dependencies (do this FIRST, before any version bump)

```powershell
flutter pub upgrade --major-versions
flutter pub outdated
```

- `--major-versions` rewrites `pubspec.yaml` constraints for DIRECT
  dependencies to the newest majors and updates `pubspec.lock`. Commit both
  files when anything changed.
- In the `flutter pub outdated` output, only **direct dependencies** and
  **dev_dependencies** rows are actionable. Transitive rows pinned by the
  Flutter SDK (`test_api`, `material_color_utilities`) or by build tooling
  (`analyzer`, `_fe_analyzer_shared`, `source_gen`, `cli_util`,
  `package_config`) cannot be moved — do not chase them, and tell the user
  they are expected noise.
- If a major bump lands (e.g. a firebase package), run the full test suite
  before accepting it; revert the single package if it breaks and note why.
- Goal: dependabot should have nothing to report for direct deps.

## 2. Quality gates

```powershell
flutter analyze
flutter test
```

Both must be completely clean. CI runs the same on Ubuntu — if a lint could
differ, trust CI's Flutter version (keep local Flutter == CI, currently the
`stable` channel).

## 3. Version bump (two files, always together)

- `pubspec.yaml` → `version: X.Y.Z+N` (N must be higher than the last Play
  upload; check the previous release/tag).
- `lib/core/app/app_version.dart` → `appVersionName` and `appVersionCode`
  must match pubspec exactly (`test/app_version_test.dart` enforces it).

```powershell
flutter test test/app_version_test.dart
```

## 4. Ship

1. Commit on `develop` (commit rules in `secrets/AGENTS.md`: conventional
   message, no Co-Authored-By, never mention AI).
2. `git push`, then PR `develop` → `main`; wait for the "Analyze and Test"
   check, then merge.
3. `git checkout main && git pull`, then tag and push the tag:

```powershell
git tag vX.Y.Z
git push origin vX.Y.Z
```

4. The tag triggers `.github/workflows/release-android.yml`, which builds a
   **signed** APK + AAB (keystore comes from repo secrets
   `ANDROID_KEYSTORE_*`) and attaches both to the GitHub release. No local
   builds. Verify with:

```powershell
gh run list --workflow release-android.yml --limit 1
gh release view vX.Y.Z
```

5. Download `AndroidIRCx-Flutter-android.aab` from the release page and
   upload it to Play Console.

## Rules recap

- Deps update → gates → version bump → PR → merge → tag. Never reorder.
- Never tag from `develop`; tags live on `main` merge commits.
- If `flutter pub upgrade --major-versions` changed anything, that change
  goes into the same release PR so CI validates it before the tag.
