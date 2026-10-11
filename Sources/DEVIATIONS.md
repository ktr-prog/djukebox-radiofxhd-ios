# Deviations from the original Radiofx HD (armv7, iOS 5.1 SDK)

This is a hand-translation of the original binary, method by method (ObjC metadata + disassembly →
Objective-C, manual retain/release, `CLANG_ENABLE_OBJC_ARC = NO`). Everything below is a place where the
result is **not** a 1:1 copy, and why. Method names, ivar names and control flow follow the binary;
constants (frames, delays, durations) were read from the disassembly.

## 1. Dead backend (Tobit servers are gone) – dropped or made inert

| Feature | What happens now |
|---|---|
| Live radio tile (folder `-33`), channel ring, EPG, stream metadata | Not built. `IsOnline` returns NO. Helper methods (`IsEPGChannel:`, `EPGNowNoti*`, `NewMeta*`, `CalcRadioAniValues…`, `RestrictXValue…`) are translated but nothing calls them; the radio-ring part of `drawIntern` is omitted. |
| Promo video tile (`-55`), TP animation, help/web/video pages | `StartTPAni:` / `StartHelpPictureAni` are empty; `GetFirstVideo`/`InitHelpPic` are stubs. |
| Card reader / pay-per-song (`AskForCard`, `SARequestThread`, `CardFound:` …) | Only reachable when `m_isstattalm` is set; cancel path is inert, `SARequestThread` is empty. |
| Advertising ticker (`AdvertTimerFunc*`) | Translated; never fires (`reserved_i1 == 0`, no advertising texts). |
| Remote control (`m_rcon`, `InsertIntoRemoteQueue…`, `RCSendVolume`) | `m_rcon` is never created; the queue methods return immediately. |
| Spotify (`SpotifyPicSaved:`, `DeleteSpotifySong:`, …) | Translated, never triggered (scrapped beta feature). |
| Second-server table (`GetSecSvr`) | `nil`. |
| Self update (`UpdateDownloaded:`, `DoTheUpdate:`, ZipArchive) | Dropped. |
| Replication from the server (`MarkFilesOnce`, `StartCopyThread:`), `CheckLastDirectChannel`, jingles, ambience, Facebook, printing | Dropped (no server). |
| `GetSongPictureFor:withinterpret:` (songdetails web service) | Returns `nil`. |
| `ServerComm DeleteOrphanServerFolders` | **Not called.** It deleted every directory under Documents not named after a known server – i.e. the user's own music. |
| `AdaptToLocalLibrary` (ServerComm) | Added: matches the server entry to the local library so the app starts without a server. |

## 2. Files are never deleted from the user's Documents folder (on purpose)

* `KioskView CheckPendingSong` clears `m_clipstodelete` instead of removing the mp3/cover files.
* `GLView DeleteSongsWithFolder:justSingleSong:`, `CheckToDeleteFolder*:` and `RenameFolder:` are translated
  faithfully (they *do* delete / rename files) but are only reachable from the Spotify notification
  (`DeleteSpotifySong:`), which is never posted. Do not wire them to UI without reviewing that.

## 3. arm64 / modern-iOS replacements

* `AVAudioSession` replaces `AudioSession*` C API; `MultichannelMixerController` clamps the render-callback read
  request to the buffer size (the 32-bit build relied on a wider `SoundBuffer`; it is `calloc`'d here).
* `sizeWithFont:` → `sizeWithAttributes:`, `UITextAlignment*` → `NSTextAlignment*`, `shouldAutorotate…`
  replaced by `shouldAutorotate` / `supportedInterfaceOrientations`, window gets a root view controller.
* `NSRegularExpression` wrapper `NSString+RegexCompat` replaces RegexKit.
* `NSInteger`/`long long` widths: ids are `long long` everywhere (the binary used pairs of registers).
* `gv_texsize` / `gv_texsizeradio` (texture edges, 196 / 512) became non-static globals so the prescroller
  thread can use them.
* `GetOGLScreenshot`: the flipped pixel buffer is intentionally not freed (the original passed no release
  callback to `CGDataProviderCreateWithData` either).

## 4. Small intentional changes

* Missing `roter-kreis-fp-new*.png` (never in the bundle): the red-dot badge falls back to `roter-kreis-fp.png`
  (same 56×60 layout).
* `BlackAndWhitePicture:withfolderid:` and a few other image helpers skip drawing when the image is `nil`
  (the original crashed or drew garbage).
* `FitGLViewForiPhone:` is a no-op on iPad.
* Initial volume: a fresh install (no `keykioskvolume`) uses 0.3 – the original's own fallback – instead of 0.
* Last played folder is one of the dropped virtual folders: the first real folder is selected.
* `ExtractPicture:` opens the mp3 read-only (the original opened it read/write for `RepairHeader`).
* `GLView ShowOnlyFolder:`: the cross-fade screenshot of the previous folder is left out; the long-distance
  spin jumps 13 covers in front of the target instead of removing the covers in between from the list.
* `InitFlipping:` (track list on the back of a cover) is implemented in `GLView_Flip.m`; it only triggers for
  covers that carry `m_tracks` (stacked albums). iPhone-only values were taken as found even where they look odd
  (negative duration-label width, cell height 0), since the app only ever ran this on iPad.
* Helper methods that exist only because the original inlined the same code twice: `flipCleanup`,
  `deleteMatches:single:folder:`, `deleteFilesOfClip:fm:` (GLView).
* `KioskView m_nowdict` is created lazily.
* `PrescrollerThread` keeps an original quirk: if the **last** folder has no songs the DB lock taken at the
  start of the loop is not released.

## 5. Not part of the port

Classes that only served the dead backend or removed third-party code were not translated:
AsyncSocket & friends, AudioStreamer, ClipStreamConnection, XML readers, EPG/ChannelInfos classes, LoginView,
HelpPicture / MenuView / StartImageView / TStartupView / FirstHint and other startup & help UI, Reachability,
SmartBroadcast, RemoteCtrlServer, ZipArchive. They are forward-declared where a header mentions them.

## Demo library (port addition)
`Sources/TestLibrary.[hm]` and `Resources/TestMusic/` (3 generated 30 s tones with covers). On launch, if the
database has no songs at all, the files are copied to `Documents/<SERVER>/1-Test Songs/` and matching
`MTFolders`/`Mixxtapes` rows are inserted. A library with any song is never touched. To remove the feature:
delete both and the one call in `KioskView.m`.

## Loading screen threshold
`KioskView CheckLoadingscreen`: the "Fast geschafft ... my.djukebox.com" screen is shown only when the library has 0 songs (original: fewer than 10).

## Port additions (audio / UI)
- Sample-rate readout (top left of the main view): file rate, engine rate, device rate, shows "(no resampling)" when all match.
- Status bar and home indicator hidden through `prefersStatusBarHidden` / `prefersHomeIndicatorAutoHidden` in iPadMainVC.
- Queue arrays use `rfx_*` accessors; a clip removed from the queue is kept alive for 10 s because several ivars (e.g. m_cliptorotate) and delayed selectors point at clips without retaining them. FinalDelete clears the clip's (assign) view pointers.
- Audio engine is Float32 with a ring buffer per bus, Now Playing / remote commands were added, and the coverflow angle constant was corrected by 1.5 degrees.

## Import folder (port addition)
`Documents/Import` (Files app > On My iPad > Radio.fx > Import) is scanned at every start (`MusicImporter`). mp3, m4a, aac, wav, aif(f), caf and flac files are moved into the library; sub-folders of Import become coverflow folders, loose files go to "Imported". Title, artist, album and cover come from the tags (fallbacks: "Artist - Title" file name, a same-named jpg/png, cover.jpg/folder.jpg, otherwise a coloured tile). The status pop-ups ("Demo library", "Audio status", "Play status") were removed; they only log now.
The round cover image is composed with a destination-in blend instead of CGContextClipToMask, which no longer honours the alpha of the circle picture on current iOS.
