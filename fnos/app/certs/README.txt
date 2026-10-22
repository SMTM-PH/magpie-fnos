cacert.pem is the Mozilla CA root bundle from https://curl.se/ca/cacert.pem
(bundle date: 2026-10-20), distributed under the Mozilla Public License 2.0.

The package uses it as the trust store for magpie, Bun, curl and Python MCP
servers, so HTTPS works even on systems without ca-certificates. To trust an
additional CA (for example a corporate TLS proxy), put its PEM certificate in
/vol*/@appdata/magpie/ca-cert.pem and restart the app.
