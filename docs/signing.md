# Signing

Tinycast is signed with a **stable self-signed identity** called `Tinycast Self-Signed`. It's not an
Apple Developer ID (there's no paid Apple account), but keeping the *same* identity on every build is
what makes macOS remember the Accessibility permission across rebuilds and updates — ad-hoc signing
changes every build and macOS forgets the grant.

You create this identity **once**. The same identity is used for:

- **local dev builds** — so Accessibility persists while you develop (the Xcode project signs with it), and
- **CI releases** — exported into two GitHub secrets the release workflow imports.

## 1. Create the `Tinycast Self-Signed` identity (once)

Run these in a terminal. They generate a self-signed code-signing certificate and import it into your
login keychain:

```sh
# Generate a self-signed code-signing cert (10-year, codeSigning use).
openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
  -keyout /tmp/tc-key.pem -out /tmp/tc-cert.pem \
  -subj "/CN=Tinycast Self-Signed" \
  -addext "basicConstraints=critical,CA:false" \
  -addext "keyUsage=critical,digitalSignature" \
  -addext "extendedKeyUsage=critical,codeSigning"

# Bundle it as a .p12 (the non-empty password keeps `security import` happy).
openssl pkcs12 -export -inkey /tmp/tc-key.pem -in /tmp/tc-cert.pem \
  -name "Tinycast Self-Signed" -out /tmp/tc.p12 -passout pass:tinycast

# Import into the login keychain so codesign can use it without prompting.
security import /tmp/tc.p12 -k ~/Library/Keychains/login.keychain-db \
  -P tinycast -A -T /usr/bin/codesign

rm -f /tmp/tc-key.pem /tmp/tc-cert.pem /tmp/tc.p12
```

Verify it's there:

```sh
security find-identity -p codesigning | grep "Tinycast Self-Signed"
```

Now local builds (Xcode, VS Code F5, `xcodebuild`) sign with it, and you grant Accessibility once.

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
gh secret set SIGNING_P12_BASE64   --repo abue-ammar/tinycast < /tmp/signing.p12.base64
gh secret set SIGNING_P12_PASSWORD --repo abue-ammar/tinycast --body "$P12_PASSWORD"
rm -f /tmp/signing.p12.base64   # holds your private key — delete it
```

If you ever lose the secrets, just re-run this section — as long as the `Tinycast Self-Signed`
identity is still in your keychain, the exported identity is the same, so users are unaffected.

## 3. Generate the Sparkle EdDSA key (once)

[In-app updates](updates.md) are signed with an Ed25519 key separate from the code-signing
identity. It lives in the login keychain the same way the identity does — service
`https://sparkle-project.org`, account `ed25519` — and, like the identity, you create it once and
never rotate it.

The matching public key is already in `Tinycast/Info.plist` as
`SUPublicEDKey` = `OsIfXjEIsBSnebzgkLBB4ChJlKe32Kw2KW+EHtmc/Sw=`, so the key below is not a new one to
invent: it is the private half of that, exported out of the keychain and handed to CI.

`generate_keys` ships in Sparkle's release tarball, which unpacks **flat** (no top-level directory),
so give it a directory of its own:

```sh
curl -fsSL -o /tmp/sparkle.tar.xz \
  https://github.com/sparkle-project/Sparkle/releases/download/2.9.4/Sparkle-2.9.4.tar.xz
mkdir -p /tmp/sparkle && tar -xJf /tmp/sparkle.tar.xz -C /tmp/sparkle

# Export the existing private key from the login keychain (approve the dialog if asked).
# Run it with no arguments first if the key doesn't exist yet — that generates and stores it,
# and prints the public key to put in Info.plist.
/tmp/sparkle/bin/generate_keys -x /tmp/sparkle-ed.key

gh secret set SPARKLE_ED_PRIVATE_KEY --repo abue-ammar/tinycast < /tmp/sparkle-ed.key

rm -rf /tmp/sparkle /tmp/sparkle.tar.xz
rm -f /tmp/sparkle-ed.key   # holds your private key — delete it
```

The release workflow uses that secret to sign each DMG and stamp the signature into the channel's
appcast. Without it, releases still publish but no client will accept them.

## What losing a key actually costs

Sparkle validates an update if **either** the EdDSA signature checks out **or** the new bundle matches
the old bundle's code-signing designated requirement, so the `.p12` and the EdDSA key are *both*
load-bearing and **either one alone can recover the update channel**. Losing one is survivable; losing
both leaves every existing install with no in-app path forward.

That matters more here than it would elsewhere, because Sparkle's usual escape hatch doesn't exist for
us. Its key-rotation fallback — accepting an update signed by a new key when the bundle still
validates against a Developer ID — hardcodes `anchor apple generic`, which a self-signed certificate
can never satisfy. So there is no "sign with the new key and let the old code signature vouch for it"
recovery here.

Practically:

- **Lost the CI secrets, still have the keychain** — re-run §2 and §3. Nothing changes for users.
- **Lost the code-signing identity, still have the EdDSA key** — recreate the identity (§1), re-do §2.
  Updates keep flowing on the EdDSA signature; existing users re-grant Accessibility once on that
  update, then it's stable again.
- **Lost the EdDSA key, still have the identity** — generate a new one (§3, no arguments) and update
  `SUPublicEDKey`. Updates keep flowing on the code-signature match.
- **Lost both** — existing installs can no longer be updated in place. Back up the login keychain.

## Quarantine (separate from signing)

macOS quarantines anything downloaded from the internet, and Gatekeeper blocks even a correctly
self-signed app with an "unverified developer" warning. The Homebrew cask runs
`xattr -dr com.apple.quarantine` in `postflight`, so **brew users never touch it**. People who
download the DMG directly clear it once by hand. In-app updates need neither: Sparkle strips the
attribute from the bundle it installs (see [updates.md](updates.md)).
