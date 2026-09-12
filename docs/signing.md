# Signing

Tinycast is signed with a **stable self-signed identity** called `Tinycast Self-Signed`. Keeping the
_same_ identity on every build is what makes macOS remember the Accessibility permission across
rebuilds and updates — ad-hoc signing changes every build and macOS forgets the grant.

An Apple Developer ID certificate now exists, but nothing is signed with it yet. Why that switch is
staged rather than immediate is [below](#the-developer-id-migration).

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
identity is still in your keychain, the exported identity is the same, so users are unaffected. If you
lose the identity entirely, recreate it (step 1) and re-do this; existing users will re-grant
Accessibility once on their next update, then it's stable again.

## Hardened runtime

Every build — local and CI, both targets — is signed with `ENABLE_HARDENED_RUNTIME: YES`, which
notarization requires. The flag is not part of the designated requirement, so turning it on costs no
Accessibility grant. Two exceptions in `Tinycast/Tinycast.entitlements` earn their place:

| Entitlement | Without it |
| --- | --- |
| `com.apple.security.cs.allow-jit` | JavaScriptCore cannot JIT, and every extension command runs on the interpreter |
| `com.apple.security.automation.apple-events` | Every Apple event is refused with `-1743` and no prompt — Get Info, the Finder selection an extension reads, and the System Events–driven system actions all die silently |

Nothing else is needed: the only `dlopen` is Apple's own IOBluetooth, so library validation is left
on, and `node`, `ray` and shell commands are separate processes it never reaches.

`./Scripts/verify-signature.sh <path-to-.app>` asserts all of this — the runtime flag on the app *and*
on `Contents/Helpers/ClipboardTextHelper`, an intact nested seal, and no `get-task-allow`. Both
release jobs run it before packaging, because a nested binary missing the runtime flag is the most
common notarization rejection there is.

## The Developer ID migration

`BundleSignature` already accepts a bundle signed by the Tinycast team under Apple's Developer ID
chain, even though releases are still signed with `Tinycast Self-Signed`. That is deliberate and
staged: the updater compares signatures before it installs, so the code that trusts the new identity
has to reach users *before* the first build carrying it. Until the switch it also accepts the running
app's own leaf, which is the only thing a copy installed earlier knows how to check.

The requirement pins the team rather than the certificate, so a Developer ID renewal strands nobody.
It deliberately omits the `notarized` keyword — that resolves a ticket through `syspolicyd` or the
network, and the updater verifies in a cache directory Gatekeeper has never assessed, so an offline
Mac would refuse a bundle the chain already proves is ours.

**The Developer ID identity stays a CI-only fact.** When the switch happens it is named on the
release workflow's `xcodebuild` line and nowhere else: `project.yml` keeps signing with
`Tinycast Self-Signed`, so a contributor keeps building with the one they created in §1 — same name,
their own key, never shared. Nothing about local development changes.

**Keep `Tinycast Self-Signed` in the login keychain after the switch.** It is the only way to ship a
build that a copy predating the migration could still install.

## Quarantine (separate from signing)

macOS quarantines anything downloaded from the internet, and Gatekeeper blocks even a correctly
self-signed app with an "unverified developer" warning. The Homebrew cask runs
`xattr -dr com.apple.quarantine` in `postflight`, so **brew users never touch it**. People who
download the DMG directly clear it once by hand.
