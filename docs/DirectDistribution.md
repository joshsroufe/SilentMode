# Direct Distribution

Silent Mode depends on changing local macOS alert sound preferences. The Mac App Store sandbox blocks those global preference writes, so paid direct distribution should use a Developer ID signed and notarized build.

## Distribution Flow

1. Build a Release archive.
2. Export with the Developer ID method.
3. Verify the app signature.
4. Package the exported app as a DMG.
5. Notarize and staple the DMG.
6. Upload the DMG to the website or GitHub Releases.
7. Sell licenses through a hosted checkout.

## Payment Flow

The first paid release should use a hosted merchant of record such as Lemon Squeezy or Paddle.

Recommended first pass:

1. Create a one-time product for Silent Mode.
2. Enable license keys.
3. Set a reasonable activation limit, such as 2 or 3 Macs per license.
4. Put the checkout link on the website.
5. Email the license key automatically from the payment provider.
6. Add license activation in the app once the product and API details exist.

## License Behavior

Silent Mode should keep licensing low-friction:

1. Ask for a license key after install.
2. Activate the key with the provider license API.
3. Store the license key and activation instance in Keychain.
4. Cache the last valid response locally.
5. Allow an offline grace period so the toggle does not depend on network access.
6. Validate again occasionally, and on app updates.

Do not make the core silent-mode toggle wait on the network after activation.

## Build Script

Run:

```sh
./script/build_release.sh
```

Optional environment variables:

```sh
DEVELOPER_ID_APPLICATION="Developer ID Application: Joshua Sroufe (GUA7MK96W5)"
NOTARYTOOL_PROFILE="SilentModeNotary"
```

`NOTARYTOOL_PROFILE` should point at credentials previously stored with `xcrun notarytool store-credentials`.

The script writes the exported app and DMG under `dist/`.

## Release Checklist

Before publishing:

1. Increment `MARKETING_VERSION` or `CURRENT_PROJECT_VERSION`.
2. Build the DMG with `./script/build_release.sh`.
3. Confirm notarization succeeds.
4. Download the DMG from the final public URL on a Gatekeeper-enabled Mac.
5. Confirm the app launches without extra warnings.
6. Confirm Silent Mode can turn on and off.
7. Confirm notification sounds restore after turning Silent Mode off.
8. Publish the download link behind the checkout/license flow.
