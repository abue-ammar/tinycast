import { base64ToBytes, bytesToBase64, utf8Encode } from "../polyfills.js";
import { hostCall, hostCallSync } from "../host.js";
import { nestedEnums } from "./enums.generated.js";

function generateRandomBytes(length) {
  const base64 = hostCallSync("crypto", "random", [length]);
  return base64ToBytes(base64);
}

function base64UrlEncode(bytes) {
  return bytesToBase64(bytes).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function generateCodeVerifier() {
  const bytes = generateRandomBytes(32);
  return base64UrlEncode(bytes);
}

function computeCodeChallenge(verifier) {
  const verifierBytes = utf8Encode(verifier);
  const hashBase64 = hostCallSync("crypto", "hash", ["sha256", bytesToBase64(verifierBytes), null]);
  const hashBytes = base64ToBytes(hashBase64);
  return base64UrlEncode(hashBytes);
}

function generateRandomString(length = 16) {
  const bytes = generateRandomBytes(length);
  return base64UrlEncode(bytes);
}

function generateState(client) {
  // raycast.com/redirect expects state to be a JSON object (base64url-encoded)
  // containing providerName and scheme ("tinycast") so it redirects to tinycast://oauth
  const payload = {
    token: generateRandomString(16),
    providerName: client?.providerName || "",
    providerId: client?.providerId || "",
    scheme: "tinycast",
  };
  const json = JSON.stringify(payload);
  const bytes = utf8Encode(json);
  return base64UrlEncode(bytes);
}

export class TokenSet {
  constructor(options = {}) {
    this.accessToken = options.accessToken ?? options.access_token ?? "";
    this.refreshToken = options.refreshToken ?? options.refresh_token;
    this.idToken = options.idToken ?? options.id_token;
    this.tokenType = options.tokenType ?? options.token_type ?? "Bearer";
    this.scope = options.scope;
    this.expiresIn = options.expiresIn ?? options.expires_in;
    this.createdAt = options.createdAt ?? Date.now();
  }

  isExpired() {
    if (this.expiresIn == null) return false;
    const expiresAt = this.createdAt + (this.expiresIn - 30) * 1000;
    return Date.now() >= expiresAt;
  }
}

export class PKCEClient {
  constructor(options = {}) {
    this.redirectMethod = options.redirectMethod || nestedEnums.OAuth.RedirectMethod.Web;
    this.providerName = options.providerName || "";
    this.providerIcon = options.providerIcon;
    this.providerId = options.providerId || "";
    this.description = options.description || "";
  }

  async authorizationRequest(options) {
    if (!options || !options.endpoint || !options.clientId) {
      throw new Error("authorizationRequest requires endpoint and clientId");
    }

    const codeVerifier = generateCodeVerifier();
    const codeChallenge = computeCodeChallenge(codeVerifier);
    const codeChallengeMethod = "S256";
    const state = options.state || generateState(this);

    let redirectURI = options.extraParameters?.redirect_uri;
    if (!redirectURI) {
      if (this.redirectMethod === nestedEnums.OAuth.RedirectMethod.App) {
        redirectURI = "raycast://oauth?package_name=Extension";
      } else if (this.redirectMethod === nestedEnums.OAuth.RedirectMethod.AppURI) {
        redirectURI = "com.raycast:/oauth?package_name=Extension";
      } else {
        redirectURI = "https://raycast.com/redirect?packageName=Extension";
      }
    }

    const url = new URL(options.endpoint);
    url.searchParams.set("response_type", "code");
    url.searchParams.set("client_id", options.clientId);
    if (options.scope) {
      url.searchParams.set("scope", options.scope);
    }
    url.searchParams.set("redirect_uri", redirectURI);
    url.searchParams.set("code_challenge", codeChallenge);
    url.searchParams.set("code_challenge_method", codeChallengeMethod);
    url.searchParams.set("state", state);

    if (options.extraParameters) {
      for (const [key, value] of Object.entries(options.extraParameters)) {
        if (value !== undefined && value !== null) {
          url.searchParams.set(key, String(value));
        }
      }
    }

    return {
      endpoint: options.endpoint,
      clientId: options.clientId,
      scope: options.scope,
      codeVerifier,
      codeChallenge,
      codeChallengeMethod,
      state,
      redirectURI,
      toURL() {
        return url.toString();
      },
    };
  }

  async authorize(request) {
    const url =
      typeof request === "string"
        ? request
        : request?.toURL
        ? request.toURL()
        : request?.url || request?.endpoint;
    if (!url) {
      throw new Error("authorize requires a valid authorization URL");
    }
    const state = typeof request === "object" ? request?.state : undefined;

    let res = await hostCall("oauth", "authorize", [url, state, this.providerId]);

    if (typeof res === "string") {
      try {
        res = JSON.parse(res);
      } catch {}
    }

    return {
      authorizationCode: res?.authorizationCode ?? res?.code ?? "",
      accessToken: res?.accessToken,
      state: res?.state,
    };
  }

  async getTokens() {
    let raw = await hostCall("oauth", "getTokens", [this.providerId]);
    if (!raw) return undefined;
    if (typeof raw === "string") {
      try {
        raw = JSON.parse(raw);
      } catch {
        return undefined;
      }
    }
    return new TokenSet(raw);
  }

  async setTokens(tokens) {
    const json = typeof tokens === "string" ? tokens : JSON.stringify(tokens);
    await hostCall("oauth", "setTokens", [this.providerId, json]);
  }

  async removeTokens() {
    await hostCall("oauth", "removeTokens", [this.providerId]);
  }
}
