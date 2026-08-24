# dsh-pet HEVC-alpha compatibility patch

WKWebView does not composite the plugin's VP9-alpha WebM assets correctly. Chrome
continues to use WebM; WebKit uses matching HEVC-with-alpha MOV assets.

Apply the code patch and generate the MOV assets in the installed plugin:

```sh
./install.sh
```

The converter decodes WebM with `libvpx-vp9` and streams BGRA frames into an
AVFoundation encoder using `AVVideoCodecType.hevcWithAlpha`. It intentionally
keeps the original WebM files for Chromium browsers.

The host-side MIME map is loaded when DSH starts, so restart DSH after applying
the patch. Re-running `install.sh` is safe and skips current MOV files.
