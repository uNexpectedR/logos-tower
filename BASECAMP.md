# Basecamp install

## Catalog URL (paste into Basecamp)

```
https://raw.githubusercontent.com/uNexpectedR/logos-tower/cursor/logos-tower-558f/logos-repo.json
```

Basecamp → **Settings → Package Repositories** (or Package Manager → Add repository) → paste the URL → Add.

## Status

| Piece | State |
| --- | --- |
| Catalog identity (`logos-repo.json`) | Published on this branch |
| Package index | Published — **no `.lgx` packages yet** |
| Installable Basecamp app | **Not ready** |

Logos Tower today matches the **ForumerMobile** shape: browser UI + Node relay to logos.dev (`@waku/sdk` + TCP). That is not a Qt/Logos Core `.lgx` module. Forumer itself installs from a catalog with native plugins; the phone/web client does not.

Until a `logos_tower` (or similar) UI/core module is built with `logos-module-builder` / Nix and released into `catalog/index.json`, Package Manager will show an empty catalog after you add the URL.

## Run the web app now

```bash
git clone https://github.com/uNexpectedR/logos-tower.git
cd logos-tower && git checkout cursor/logos-tower-558f
npm install && npm run dev
```

## To make Basecamp Install work later

1. Scaffold a Logos UI module (`nix flake init -t github:logos-co/logos-module-builder/0.3.2#ui-qml` or `#ui-qml-backend`).
2. Prefer `delivery_module` for Waku instead of the Node TCP relay where possible.
3. `nix build '.#lgx-portable'`, publish the `.lgx` on a GitHub release, rebuild `catalog/index.json` (see [logos-modules-release-base](https://github.com/logos-co/logos-modules-release-base)).
4. Users keep using the same `logos-repo.json` URL above.
