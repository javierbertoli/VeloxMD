# Development dependencies

## Flutter SDK (stable, ≥ 3.27)

Needed to build and run tests (`flutter test`). Not packaged in Debian/Ubuntu;
install from the official tarball:

```bash
curl -fsSL https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_3.47.6-stable.tar.xz \
  | tar -xJ -C /opt
export PATH=/opt/flutter/bin:$PATH
flutter pub get
```

The tarball extraction requires `xz-utils`; Flutter itself requires `git`
and `unzip`. In the ai-pod container these are installed by
`ai-pod.Dockerfile`.
