# Distribution and notarization

The release workflow intentionally creates an unsigned development build because signing identities and notarization credentials must never be committed to a repository.

For production distribution outside the Mac App Store:

1. Join the Apple Developer Program and create a **Developer ID Application** certificate.
2. Import the certificate into the CI runner's temporary keychain from an encrypted GitHub Actions secret.
3. Archive with hardened runtime enabled and sign all nested code with that identity.
4. Create the DMG and sign the DMG itself.
5. Submit it with `xcrun notarytool submit --wait` using an App Store Connect API key stored as GitHub secrets.
6. Run `xcrun stapler staple` and verify with `spctl --assess --type open` before publishing the release.

Recommended secret names are `DEVELOPER_ID_CERTIFICATE_P12`, `DEVELOPER_ID_CERTIFICATE_PASSWORD`, `APP_STORE_CONNECT_KEY_ID`, `APP_STORE_CONNECT_ISSUER_ID`, and `APP_STORE_CONNECT_PRIVATE_KEY`. Use a dedicated least-privilege App Store Connect API key and a temporary CI keychain that is deleted at the end of the job.

Do not enable the App Sandbox without redesigning folder access around user-selected security-scoped bookmarks. A cleaner needs access to several user Library locations, while macOS privacy protections can still require explicit Full Disk Access.
