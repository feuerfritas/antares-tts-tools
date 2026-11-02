# Building the Mundane saved object

The Mundane Importer and Mundane Controller can be built as one Tabletop Simulator
saved object (a `.json` plus a `.png` thumbnail for the Saved Objects menu) with
[tts-mod-composer](https://gitlab.com/feuerfritas/tts-mod-composer). Each object's
JSON shell in `tools/<tool>/` points at that folder's `tool.lua`, and the composer
inlines the script into it, so the result always carries the Lua in this repo.
`build/TTSModfile.yaml` tells the composer where the objects are.

The GitHub workflow `.github/workflows/build-objects.yml` runs exactly this on every
push and attaches the result to a release on every `v*` tag.

## Locally

Install the composer (see its [releases page](https://gitlab.com/feuerfritas/tts-mod-composer/-/releases);
`pipx install "git+https://gitlab.com/feuerfritas/tts-mod-composer.git@v0.18.0"` works anywhere), then from the repo root:

```sh
mkdir -p out
tts-mod-composer build-object \
  tools/MundaneImporterN26byAntares77.e4e1fb \
  tools/MundaneControllerN26byAntares77.e27378 \
  -f build/TTSModfile.yaml \
  -o out/mundane-tools.json \
  --stamp "$(git describe --tags --always)"
```

Copy `out/mundane-tools.json` and `out/mundane-tools.png` into TTS's
`Saves/Saved Objects/` folder. The composer refuses to `--stamp` a dirty working
tree; add `--allow-dirty` while experimenting.
