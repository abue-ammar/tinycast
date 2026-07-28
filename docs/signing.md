# Signing

Smallcast is signed with a **stable self-signed identity** called `Smallcast Self-Signed`. It's not an
Apple Developer ID (there's no paid Apple account), but keeping the *same* identity on every build is
what makes macOS remember the Accessibility permission across rebuilds and updates — ad-hoc signing
changes every build and macOS forgets the grant.

You create this identity **once**. The same identity is used for:

- **local dev builds** — so Accessibility persists while you develop (the Xcode project signs with it), and
- **CI releases** — exported into two GitHub secrets the release workflow imports.

## 1. Create the `Smallcast Self-Signed` identity (once)

Run these in a terminal. They generate a self-signed code-signing certificate and import it into your
login keychain:

```sh
# Generate a self-signed code-signing cert (10-year, codeSigning use).
openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
  -keyout /tmp/tc-key.pem -out /tmp/tc-cert.pem \
  -subj "/CN=Smallcast Self-Signed" \
  -addext "basicConstraints=critical,CA:false" \
  -addext "keyUsage=critical,digitalSignature" \
  -addext "extendedKeyUsage=critical,codeSigning"

# Bundle it as a .p12 (the non-empty password keeps `security import` happy).
# Use the *system* openssl here: OpenSSL 3 (what Homebrew installs, and what's first in PATH if you
# have it) defaults to a SHA-256 MAC with AES-256, which Apple's SecPKCS12Import can't read — the
# import then fails with "MAC verification failed during PKCS12 import (wrong password?)".
# macOS's LibreSSL always writes the legacy SHA-1/3DES form Security understands.
/usr/bin/openssl pkcs12 -export -inkey /tmp/tc-key.pem -in /tmp/tc-cert.pem \
  -name "Smallcast Self-Signed" -out /tmp/tc.p12 -passout pass:smallcast

# Import into the login keychain so codesign can use it without prompting.
security import /tmp/tc.p12 -k ~/Library/Keychains/login.keychain-db \
  -P smallcast -A -T /usr/bin/codesign

rm -f /tmp/tc-key.pem /tmp/tc-cert.pem /tmp/tc.p12
```

Verify it's there:

```sh
security find-identity -p codesigning | grep "Smallcast Self-Signed"
```

Now local builds (Xcode, VS Code F5, `xcodebuild`) sign with it, and you grant Accessibility once.

If you'd rather stay on one `openssl`, adding `-legacy` to the OpenSSL 3 `pkcs12 -export` line produces
the same compatible bundle. To build without any of this (no signing, so macOS forgets the
Accessibility grant on every rebuild): `xcodebuild … CODE_SIGNING_ALLOWED=NO`.

## 2. Generate the CI secrets

The release workflow needs the same identity as two repo secrets. Export it, base64-encode it, and
pick a password:

```sh
# Pick a random password for the exported bundle.
P12_PASSWORD="$(openssl rand -base64 24)"; echo "password: $P12_PASSWORD"

# Export the identity (approve the keychain dialog if asked) and base64-encode it.
security export -t identities -f pkcs12 \
  -k ~/Library/Keychains/login.keychain-db \
  -P "$P12_PASSWORD" -o /tmp/signing.p12
base64 -i /tmp/signing.p12 | tr -d '\n' > /tmp/signing.p12.base64
rm -f /tmp/signing.p12
```

Then set the two secrets on the repo (via `gh`, authed as the repo owner, or paste them in the GitHub
UI under **Settings → Secrets and variables → Actions**):

```sh
gh secret set SIGNING_P12_BASE64   --repo arthur-fontaine/tinycast < /tmp/signing.p12.base64
gh secret set SIGNING_P12_PASSWORD --repo arthur-fontaine/tinycast --body "$P12_PASSWORD"
rm -f /tmp/signing.p12.base64   # holds your private key — delete it
```

If you ever lose the secrets, just re-run this section — as long as the `Smallcast Self-Signed`
identity is still in your keychain, the exported identity is the same, so users are unaffected. If you
lose the identity entirely, recreate it (step 1) and re-do this; existing users will re-grant
Accessibility once on their next update, then it's stable again.

## Quarantine (separate from signing)

macOS quarantines anything downloaded from the internet, and Gatekeeper blocks even a correctly
self-signed app with an "unverified developer" warning. The Homebrew cask runs
`xattr -dr com.apple.quarantine` in `postflight`, so **brew users never touch it**. People who
download the DMG directly clear it once by hand.
