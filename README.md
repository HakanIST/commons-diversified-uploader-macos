# Commons Diversified Uploader (macOS)

A native macOS app for sports photographers who contribute to
[Wikimedia Commons](https://commons.wikimedia.org/). It reads jersey numbers
and jersey colours from match photos, maps them to players through the team
rosters on Wikipedia/Wikidata, proposes the matching Commons categories and
uploads the reviewed photos.

This is a community project. It is not affiliated with or endorsed by the
Wikimedia Foundation.

## How it works

1. **Match** – pick the photo folder and the two teams (Wikidata search) and
   mark each team's jersey colours for that game.
2. **Rosters** – number → player tables are read from the roster template on
   Turkish/English Wikipedia; each player is resolved to a Wikidata item and
   its Commons category (P373). Everything is editable.
3. **Analysis** – every photo is read locally with
   [Florence-2](https://huggingface.co/onnx-community/Florence-2-base-ft)
   running on ONNX Runtime (whole frame plus overlapping tiles). No photo
   leaves the computer during analysis.
4. **Review** – detected players, file name and categories are shown per
   photo and can be corrected.
5. **Upload** – chunked upload to Commons with `{{Information}}`, licence,
   categories and structured-data "depicts" statements.

Project state is stored next to the photos in `commons-yukleme.json`, in the
same format the Windows app uses.

## Building

Requirements: macOS 14+, Xcode 16+, [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
scripts/fetch-onnxruntime.sh   # ONNX Runtime from the official NuGet package
cd Packages/UploaderCore && swift test
```

```sh
xcodegen generate && open CommonsDiversifiedUploader.xcodeproj
```

The model (about 1 GB) is downloaded from Hugging Face on first use.

## Repository layout

- `Packages/UploaderCore` – analysis, roster, matching and Commons client
  (Swift package with unit tests and a `cdu-cli` development tool)
- `App` – SwiftUI application
- `scripts` – build helpers

## Contributing

Commit messages follow the
[Wikimedia commit message guidelines](https://www.mediawiki.org/wiki/Gerrit/Commit_message_guidelines).

## License

[Apache License 2.0](LICENSE)
