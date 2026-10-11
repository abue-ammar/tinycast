// Raycast's OAuth PKCE client (RFC 7636). Swift runs the browser sign-in and stores token sets.

import { hostCall } from "../host.js";
import { nodeModules } from "../node-shims.js";
import { nestedEnums } from "./enums.generated.js";

const RedirectMethod = nestedEnums.OAuth.RedirectMethod;
const clientIdMetadataDocument = "https://www.raycast.com/.well-known/oauth-client-metadata/raycast.json";

// The web redirect page forwards to `raycast://oauth`, so that scheme is what the sign-in waits for.
const redirects = {
  [RedirectMethod.Web]: { uri: "https://raycast.com/redirect?packageName=Extension", scheme: "raycast" },
  [RedirectMethod.App]: { uri: "raycast://oauth?package_name=Extension", scheme: "raycast" },
  [RedirectMethod.AppURI]: { uri: "com.raycast:/oauth?package_name=Extension", scheme: "com.raycast" },
  [RedirectMethod.ClientIdMetadataDocument]: { uri: "com.raycast:/oauth", scheme: "com.raycast" },
};

const expiryMarginSeconds = 10;

const randomURLSafe = (size) => nodeModules.crypto.randomBytes(size).toString("base64url");

class PKCEClient {
  constructor(options) {
    if (!redirects[options.redirectMethod]) throw new Error(`Unknown redirect method: ${options.redirectMethod}`);
    this.redirectMethod = options.redirectMethod;
    this.providerName = options.providerName;
    this.providerIcon = options.providerIcon;
    this.providerId = options.providerId ?? options.providerName;
    this.description = options.description;
  }

  async authorizationRequest({ endpoint, clientId, scope, extraParameters }) {
    const codeVerifier = randomURLSafe(32);
    const request = {
      clientId: clientId ?? (this.redirectMethod === RedirectMethod.ClientIdMetadataDocument ? clientIdMetadataDocument : undefined),
      codeVerifier,
      codeChallenge: nodeModules.crypto.createHash("sha256").update(codeVerifier).digest("base64url"),
      state: randomURLSafe(16),
      redirectURI: redirects[this.redirectMethod].uri,
    };
    const query = {
      response_type: "code",
      client_id: request.clientId,
      redirect_uri: request.redirectURI,
      scope,
      state: request.state,
      code_challenge: request.codeChallenge,
      code_challenge_method: "S256",
      ...extraParameters,
    };
    return {
      ...request,
      toURL() {
        const url = new URL(endpoint);
        for (const [key, value] of Object.entries(query)) {
          if (value !== undefined) url.searchParams.set(key, value);
        }
        return url.toString();
      },
    };
  }

  async authorize(request) {
    const url = typeof request.toURL === "function" ? request.toURL() : request.url;
    const redirect = await hostCall("oauth", "authorize", [url, redirects[this.redirectMethod].scheme]);
    const params = new URL(redirect).searchParams;
    const error = params.get("error");
    if (error) throw new Error(params.get("error_description") ?? error);
    // Raycast's web redirect page drops `state`, so only a returned one can be checked.
    const state = params.get("state");
    if (state !== null && request.state !== undefined && state !== request.state) {
      throw new Error(`${this.providerName} sign-in returned a mismatched state.`);
    }
    const code = params.get("code");
    if (!code) throw new Error(`${this.providerName} sign-in returned no authorization code.`);
    return { authorizationCode: code };
  }

  async setTokens(options) {
    const scope = options.scope;
    const tokens = {
      accessToken: options.accessToken ?? options.access_token,
      refreshToken: options.refreshToken ?? options.refresh_token,
      idToken: options.idToken ?? options.id_token,
      expiresIn: options.expiresIn ?? options.expires_in,
      scope: Array.isArray(scope) ? scope.join(" ") : scope,
      updatedAt: new Date().toISOString(),
    };
    await hostCall("oauth", "setTokens", [this.providerId, JSON.stringify(tokens)]);
  }

  async getTokens() {
    const stored = await hostCall("oauth", "getTokens", [this.providerId]);
    return stored ? tokenSet(JSON.parse(stored)) : undefined;
  }

  removeTokens() {
    return hostCall("oauth", "setTokens", [this.providerId, null]);
  }
}

function tokenSet(stored) {
  const updatedAt = new Date(stored.updatedAt);
  return {
    ...stored,
    updatedAt,
    isExpired() {
      if (!Number.isFinite(stored.expiresIn)) return false;
      return Date.now() >= updatedAt.getTime() + (stored.expiresIn - expiryMarginSeconds) * 1000;
    },
  };
}

export const OAuth = { PKCEClient, RedirectMethod, clientIdMetadataDocument };
