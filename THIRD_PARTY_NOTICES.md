# Third-party software

G-Link's original GUI, scripts, documentation and architectural artwork are licensed under MIT; see [LICENSE](LICENSE).
The MIT license does not replace the licenses of third-party files.

## sing-box 1.13.8

- Project: https://github.com/SagerNet/sing-box
- Upstream release: https://github.com/SagerNet/sing-box/releases/tag/v1.13.8
- License: [GNU GPL v3](bin/LICENSE-sing-box.txt), with the upstream notices retained.
- Official executables: `bin/darwin-arm64/sing-box` and `bin/darwin-amd64/sing-box`.
- Executable checksums: [bin/SHA256SUMS](bin/SHA256SUMS).
- Corresponding upstream source: [bin/sing-box-source-v1.13.8.tar.gz](bin/sing-box-source-v1.13.8.tar.gz).
- Source archive checksum and provenance: [bin/来源说明.md](bin/来源说明.md).
- Upstream build documentation: https://sing-box.sagernet.org/installation/build-from-source/

G-Link launches sing-box as a separate process. The bundled engine is not patched;
the build combines the official architecture slices and applies a local ad-hoc signature.
The original sing-box license and source information are also included in the application bundle.
The source archive retains the upstream build files, module declarations, license and documentation.
In a built app, the source archive is also available at `Contents/Resources/sing-box-source-v1.13.8.tar.gz`.
