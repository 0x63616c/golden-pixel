# iOS, target device and release

## Target: iPhone Duo, inner screen

| | |
| --- | --- |
| Inner display, rendered | 2853 x 2007 px landscape (2007 x 2853 native portrait) |
| Points | 951 x 669 pt at @3x |
| Physical panel | 1878 x 2670 px at about 430 ppi; iOS downsamples the rendered image to it (about 6.4%) |
| Fold band | about x = 455.5 to 495.5 pt when folded |

Sources: App Store Connect screenshot sizes as collected at iphoneduosupport.com/specs,
blakecrosley.com/blog/iphone-duo-for-developers, getchonky.app/blog/iphone-duo-screen-sizes and
duobreak.com. The simulator's own device profile is captured by CI as `duo-profile.json` in
the `duo-screenshots` artifact.

## The art grid

- One art pixel = **6 x 6 device pixels**. 2853 / 6 = 475, 2007 / 6 = 334, so the canvas is
  **475 x 334** art pixels (2850 x 2004 px, centred with 1.5 px to spare per side).
- A cell is **10 x 10** art pixels; the board is **33 x 33** cells = 330 art pixels square, so it
  fills the screen's height. The panel takes the remaining 141 x 334 on the right.
- Text is Pixel Operator 8 (7-pixel caps); HUD icons are 7 x 7 to match.
- The board can zoom to 2x, 3x or 4x (12, 18, 24 device pixels per board art pixel). The UI
  never zooms.
- Caveat: because the physical panel is smaller than the rendered image, the last step on real
  glass is iOS's own resample. Everything the app controls is exact (the grid check proves it
  on the rendered image and on simulator screenshots).

Other phones get the largest whole scale that fits 334 art pixels on the short side, and
letterbox.

## Run it

```sh
brew install xcodegen just
just ios-sim                 # iPhone Duo simulator ("GP Duo")
SCENE=mid just ios-sim       # a staged scene (title, start, early, mid, zoom, upgrades, late, skills, gold, portrait)
just ios-device              # a plugged-in phone (Xcode signed in to team X9E4HG27NK)
```

## Release

- App: **Golden Pixel**, bundle ID `co.worldwidewebb.goldenpixel`, team `X9E4HG27NK`, SKU `golden-pixel-001`.
- Every merge to `main` runs `.github/workflows/testflight.yml`: it archives with cloud-managed
  signing (App Store Connect API key), uploads to TestFlight, and reports the processing
  state. Builds go to the internal group **Me**. Nothing is ever submitted for review.
- `App Store Connect setup` (manual workflow) registers the bundle ID, finds or creates the
  app record and the TestFlight group. Apple doesn't let API keys create app records, so if
  it reports "No app record yet", create it once in App Store Connect (Apps > + > New App,
  the values above) and run the workflow again.
- Secrets live only in the `testflight` environment (main branch only): `ASC_KEY_ID`,
  `ASC_ISSUER_ID`, `ASC_KEY_CONTENT`. The key needs the Admin role for cloud signing.
