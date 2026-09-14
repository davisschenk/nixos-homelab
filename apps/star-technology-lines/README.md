# Starline

Starline is a Vite app for planning [Star Technology](https://github.com/StarT-Dev-Team/Star-Technology) processing lines. Search the included recipe catalog, add recipes as editable machine stages, connect matching items and fluids, and compare per-minute rates. Lines are saved in your browser and can be imported or exported as JSON.

## Run the app

```sh
cd apps/star-technology-lines
npm install
npm run dev
```

`npm run build` creates a static site in `dist/`. The committed `public/catalog.json` is included in the build; no game installation or account is needed to browse it.

## Recipe data

The bundled catalog was extracted from the pack's [Theta 1 Hotfix 3 release tag](https://github.com/StarT-Dev-Team/Star-Technology/tree/26135f37ebad21800d7ffe61f29189d6f15254ab), matching the local instance's `1.20.1-THETA-1-HOTFIX-3` version. It includes `common` and `default` scripts. Its `sources` records contain the upstream URL, commit, license, and scope; each recipe records its source path and line. Voltage constants come from the [StarT GTM fork](https://github.com/StarT-Dev-Team/GTM-StarT-Fork/blob/a73acfa666ec53a8e9efd285a296b3b97546f100/src/main/java/com/gregtechceu/gtceu/api/GTValues.java). The pack's MIT license is included in [STAR-TECHNOLOGY-LICENSE](STAR-TECHNOLOGY-LICENSE).

The source importer reads syntax trees; it never runs modpack scripts. It expands static loops and branches, recipe helpers, research builders, and Create/Vintage calls, and preserves unresolved fields for review. The catalog currently contains 5,562 source-derived declarations, including 2,572 GT recipes with deterministic inputs and outputs, duration, and EU/t. The default catalog view shows these ready recipes. Enable **Show entries that need review** to inspect the others. Some pack scripts compute recycling recipes through game material APIs, which cannot be resolved from source alone. Installed mods also generate recipes that are absent from the pack source, so this catalog is a source-derived set rather than a complete in-game recipe list.

To regenerate from a local checkout of the pack source:

```sh
npm run catalog:build -- --source-root /path/to/Star-Technology --pack-mode default --pack-version 1.20.1-THETA-1-HOTFIX-3
npm run catalog:check
npm test
```

The optional `--kubejs-export /path/to/minecraft/local/kubejs/export` argument can replace the source-derived records with JSON from `/kubejs export` in a running instance. The bundled catalog does not use that option.

The catalog schema is versioned. Each adapter produces records with a `sourceId`, source metadata, and normalized recipe fields. The build command accepts `--json /path/to/another-catalog.json` to merge another catalog, then checks source IDs and recipe keys for collisions. The app loads the resulting static `catalog.json` at runtime, so it does not depend on a particular parser or data service.
