# Golden Pixel

A native iOS idle breaker drawn entirely on a pixel grid. Every level starts in the dark:
your balls break through a buried map one pixel at a time, light spreads from every break,
and somewhere out there one golden pixel is pulsing. Break it to go deeper.

- Fully native Swift: a pure-Swift game core rasterises one low-res RGBA frame on the CPU,
  and Metal shows it at an integer scale with nearest sampling (plus an optional bloom pass).
- Built for the iPhone Duo's inner screen: a 475×334 art canvas × 6 = 2850×2004, edge to edge.
  Other iPhones get the same pixel size on a smaller canvas, and the layout fits itself to it.
- TestFlight builds come from CI on every merge to `main`.

```sh
just test        # core unit tests (Linux or macOS)
just render      # staged scenes as PNGs, no Xcode needed
just ios-sim     # run on the iPhone Duo simulator
```

Docs: [architecture](docs/architecture.md) · [design](docs/design.md) · [iOS + release](docs/ios.md) ·
[contributing](CONTRIBUTING.md) · [agents](CLAUDE.md)
