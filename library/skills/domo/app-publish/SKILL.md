---
name: domo/app-publish
description: >
  Build, validate, and publish a Domo app to an instance or the Domo Appstore
  marketplace. Handles domo publish, cross-instance copy, versioning, partner
  submission, and post-publish dataset re-mapping.
  Triggers on: "publish domo", "domo publish", "deploy app", "appstore submit", "marketplace"
---

# /domo/app-publish

> Publish a Domo custom app to your instance or the Domo Appstore marketplace.

## Purpose

Take a developed Domo app from local development to production. Handles validation, building, publishing via the Domo CLI, cross-instance deployment, versioning strategies, and Appstore partner submission requirements. Ensures datasets are properly re-mapped post-publish.

## Usage

```bash
# Publish to current instance
/domo/app-publish --target instance

# Publish update (new version)
/domo/app-publish --target instance --version 2.0.0

# Submit to Appstore marketplace
/domo/app-publish --target appstore --partner-id PARTNER123
```

## Process

### Step 1: Pre-Publish Validation
Before publishing, verify:
1. `manifest.json` is valid (name, version, size, mapping present).
2. All dataset aliases in `mapping` reference accessible datasets.
3. Build completes without errors.
4. AppDB collections (if any) have proper security filters.
5. No hardcoded instance-specific IDs in source code.

### Step 2: Build
Compile the app for production:
- React: `npm run build` → output in `build/`
- The CLI bundles assets from the configured output directory.
- Ensure `public-assets/` contains any static JS that needs external access (for embed scenarios).

### Step 3: Publish to Instance
```bash
domo publish
```
The CLI will:
1. Bundle the app source.
2. Upload to the authenticated instance.
3. Create/update the app card.
4. Return the app ID and card URL.

### Step 4: Post-Publish Dataset Wiring
After publishing, datasets must be wired in the Domo UI:
1. Navigate to the published card.
2. Open card settings > Data.
3. Map each alias to the actual instance dataset.
4. Save and verify data loads correctly.

### Step 5: Version Management
- Increment `version` in `manifest.json` before each publish.
- Use semantic versioning: `MAJOR.MINOR.PATCH`.
- Breaking changes (new required datasets) = major version bump.
- `domo publish` will update the existing app if the name matches.

### Step 6: Cross-Instance Copy
To deploy to a different instance:
1. Export the app from source instance.
2. Import to target instance.
3. Re-map all dataset aliases to target instance datasets.
4. Re-configure AppDB proxy ID if applicable.

### Step 7: Appstore Marketplace Submission (Partner)
Requirements for Appstore submission:
- App must meet Domo marketplace quality standards.
- Include comprehensive documentation and installation guide.
- Define required dataset schemas clearly.
- Support multiple instances (no hardcoded IDs).
- Submit via the Partner Developer portal.
- Include pricing model if paid app.

## Key References

- CLI command: `domo publish`
- Manifest fields: `name`, `version`, `size`, `mapping`
- Post-publish: dataset re-mapping in Domo UI
- Cross-instance: export/import pattern
- Partner submission: Domo Partner Developer portal
- `public-assets/` for externally accessible static files
- Versioning: semantic versioning (`MAJOR.MINOR.PATCH`)

## Examples

```bash
# Standard publish with version bump
/domo/app-publish --version 1.2.0

# Publish and document dataset mapping requirements
/domo/app-publish --target instance --document-mapping

# Full Appstore submission with partner metadata
/domo/app-publish --target appstore --partner-id P123 --pricing free --category analytics
```
