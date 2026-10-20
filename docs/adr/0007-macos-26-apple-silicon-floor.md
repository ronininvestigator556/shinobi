# Platform floor: macOS 26, Apple Silicon

Shinobi v1 requires **macOS 26 and Apple Silicon**, inheriting the prior tool's requirement rather than back-porting to older macOS versions or Intel. The newer floor is what lets us use current WebKit/`WKWebsiteDataStore` APIs (e.g. `proxyConfigurations`) directly and reuse the vendored kits unchanged.

The trade-off — some colleagues' older Macs can't run it — is accepted for v1 to avoid spending the whole first release on compatibility shims. Revisit if distribution demand warrants it.
