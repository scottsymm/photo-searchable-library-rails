# Apple Photos Bridge

Native macOS command-line bridge for importing Apple Photos assets into this
Rails application.

Build and run from this directory:

```bash
swift build
swift run PicsPhotosBridge --watch --api-url http://localhost:3000
```

The first run asks macOS for Photos access. Keep the bridge running while using
the Apple Photos sync controls in the Rails application.
