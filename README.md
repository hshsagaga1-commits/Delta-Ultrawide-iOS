# Delta Ultrawide iOS

Investigation workspace for testing whether Roblox Delta on iOS can render a horizontally stretched / ultrawide image without simply zooming and cropping the view.

## Device / goal
- Device reported: iPhone 11
- Platform reported: iOS 27
- Goal: explore aspect-ratio/render-area options and document safe, reversible tests.

## Before uploading files
**This repository is currently public. Do not upload the IPA here while it is public.** A public IPA could be downloaded by anyone. Change the repository visibility to Private in Settings → General → Danger Zone → Change repository visibility, then confirm that the connected GitHub integration still has access.

## Useful files to share for analysis
Prefer extracted metadata and text files first:
- `Payload/Delta.app/Info.plist` (convert to XML if needed)
- a file / directory listing of `Payload/Delta.app/`
- names of embedded frameworks and bundles
- relevant crash logs or configuration files, with personal identifiers removed

The GitHub connector can read repository files, but that does not guarantee it can inspect or decompile an uploaded binary IPA directly. Large binary files may also exceed GitHub's ordinary file-upload limits.

## Investigation notes
- No IPA has been analyzed yet.
- No changes to the app have been made.
