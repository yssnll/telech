---
name: Offline HLS on iOS
description: Reliable local playback strategy for downloaded HLS streams
---

On iOS, an HLS playlist reconstructed from local segments and opened with AVPlayer is not a reliable offline format. Convert HLS to a self-contained MP4 before saving it in the app’s private storage, then play only the local MP4.

**Why:** A download can complete and appear in the offline list while the local `m3u8` still fails to load in the native player because local HLS support is fragile and depends on playlist/segment details.

**How to apply:** Keep direct MP4 downloads local, route HLS conversion through the server’s MP4 endpoint, require the mobile build to know the public API domain, and offer a re-download path for legacy local HLS entries.