// The non-visual half of @raycast/api: clipboard, storage, cache, preferences, app lookup and the
// window/feedback calls. Everything here is an async host call answered by Swift on the main actor.

import { hostCall } from "../host.js";
import { nestedEnums } from "./enums.generated.js";

const ToastStyle = nestedEnums.Toast.Style;

let boot = { environment: {}, preferences: {}, launchProps: {} };

export function configureSystem(info) {
  boot = { ...boot, ...info };
}

export function unsupported(what) {
  return Promise.reject(
    new Error(`${what} is not supported in Tinycast extensions yet. See docs/extensions.md.`),
  );
}

// ─── Clipboard ──────────────────────────────────────────────────────

export const Clipboard = {
  copy: (content, options) => hostCall("clipboard", "copy", [normalizeClipboardContent(content), options ?? {}]),
  paste: (content) => hostCall("clipboard", "paste", [normalizeClipboardContent(content)]),
  clear: () => hostCall("clipboard", "clear", []),
  read: (options) => hostCall("clipboard", "read", [options ?? {}]),
  readText: (options) => hostCall("clipboard", "readText", [options ?? {}]),
};

function normalizeClipboardContent(content) {
  if (content === null || content === undefined) return { text: "" };
  if (typeof content === "string") return { text: content };
  if (typeof content === "number") return { text: String(content) };
  return content;
}

// ─── LocalStorage ───────────────────────────────────────────────────

export const LocalStorage = {
  async getItem(key) {
    const value = await hostCall("storage", "get", [String(key)]);
    return value === null ? undefined : value;
  },
  setItem: (key, value) => hostCall("storage", "set", [String(key), value]),
  removeItem: (key) => hostCall("storage", "remove", [String(key)]),
  clear: () => hostCall("storage", "clear", []),
  allItems: () => hostCall("storage", "all", []),
};

// ─── Cache ──────────────────────────────────────────────────────────
// Raycast's Cache is synchronous. Swift hands the whole namespace over at construction and every
// mutation is fire-and-forget write-behind, so reads stay synchronous as the API promises.

const cacheSubscribers = new Map();
let nextCacheSubscription = 1;

export class Cache {
  constructor(options = {}) {
    this.namespace = options.namespace ?? "default";
    this.capacity = options.capacity ?? 10 * 1024 * 1024;
    this._entries = new Map(Object.entries(cacheSnapshot(this.namespace)));
    this._subscribers = new Set();
    // `useCachedState` hands `cache.subscribe` straight to `useSyncExternalStore`, unbound — so every
    // method has to survive being detached from the instance.
    for (const method of ["has", "get", "set", "remove", "clear", "subscribe"]) {
      this[method] = Cache.prototype[method].bind(this);
    }
  }

  get isEmpty() {
    return this._entries.size === 0;
  }

  has(key) {
    return this._entries.has(String(key));
  }

  get(key) {
    return this._entries.get(String(key));
  }

  set(key, data) {
    this._entries.set(String(key), String(data));
    this._persist(String(key), String(data));
    this._notify(String(key), String(data));
  }

  remove(key) {
    const existed = this._entries.delete(String(key));
    if (existed) {
      this._persist(String(key), null);
      this._notify(String(key), undefined);
    }
    return existed;
  }

  clear(options = {}) {
    this._entries.clear();
    hostCall("cache", "clear", [this.namespace]).catch(() => {});
    if (options.notifySubscribers !== false) this._notify(undefined, undefined);
  }

  subscribe(subscriber) {
    const id = nextCacheSubscription++;
    this._subscribers.add(subscriber);
    cacheSubscribers.set(id, { namespace: this.namespace, subscriber });
    return () => {
      this._subscribers.delete(subscriber);
      cacheSubscribers.delete(id);
    };
  }

  _persist(key, value) {
    hostCall("cache", "set", [this.namespace, key, value]).catch(() => {});
  }

  _notify(key, data) {
    for (const subscriber of this._subscribers) {
      try {
        subscriber(key, data);
      } catch {
        // A throwing subscriber must not break the write that triggered it.
      }
    }
  }
}

/// Swift installs the initial contents of every cache namespace at boot; a namespace first touched
/// later starts empty and fills as the extension writes to it.
function cacheSnapshot(namespace) {
  return boot.caches?.[namespace] ?? {};
}

// ─── Preferences & environment ──────────────────────────────────────

export function getPreferenceValues() {
  return { ...boot.preferences };
}

export const environment = new Proxy(
  {},
  {
    get(_target, key) {
      if (key === "canAccess") return () => false;
      return boot.environment?.[key];
    },
    has: (_target, key) => key in (boot.environment ?? {}),
    ownKeys: () => Object.keys(boot.environment ?? {}),
    getOwnPropertyDescriptor: () => ({ enumerable: true, configurable: true }),
  },
);

export function openExtensionPreferences() {
  return hostCall("window", "openPreferences", ["extension"]);
}

export function openCommandPreferences() {
  return hostCall("window", "openPreferences", ["command"]);
}

// ─── Window / navigation control ────────────────────────────────────

export function closeMainWindow(options = {}) {
  return hostCall("window", "close", [options]);
}

export function popToRoot(options = {}) {
  return hostCall("window", "popToRoot", [options]);
}

export function clearSearchBar(options = {}) {
  return hostCall("window", "clearSearchBar", [options]);
}

// ─── Applications & files ───────────────────────────────────────────

export function open(target, application) {
  const app = typeof application === "string" ? application : application?.bundleId ?? application?.path;
  return hostCall("system", "open", [String(target), app ?? null]);
}

/// Raycast shows an app picker for Action.OpenWith; Swift resolves the candidates and presents them.
export function openWith(path) {
  return hostCall("system", "openWith", [String(path)]);
}

export function trash(paths) {
  return hostCall("system", "trash", [(Array.isArray(paths) ? paths : [paths]).map(String)]);
}

export function showInFinder(path) {
  return hostCall("system", "showInFinder", [String(path)]);
}

export function getApplications(path) {
  return hostCall("system", "applications", [path ? String(path) : null]);
}

export function getDefaultApplication(path) {
  return hostCall("system", "defaultApplication", [String(path)]);
}

export function getFrontmostApplication() {
  return hostCall("system", "frontmostApplication", []);
}

export function getSelectedText() {
  return hostCall("system", "selectedText", []);
}

export function getSelectedFinderItems() {
  return hostCall("system", "selectedFinderItems", []);
}

export function captureException(error) {
  console.error(error instanceof Error ? error.stack || error.message : String(error));
}

export function launchCommand(options) {
  return hostCall("system", "launchCommand", [options]);
}

export function updateCommandMetadata(metadata) {
  return hostCall("system", "updateCommandMetadata", [metadata]);
}

export function getFrontmostBrowserTab() {
  return unsupported("getFrontmostBrowserTab");
}

// ─── Feedback ───────────────────────────────────────────────────────

export class Toast {
  constructor(options = {}) {
    this._id = null;
    this._options = {
      style: options.style ?? ToastStyle.Success,
      title: options.title ?? "",
      message: options.message,
      primaryAction: options.primaryAction,
      secondaryAction: options.secondaryAction,
    };
  }

  get style() {
    return this._options.style;
  }
  set style(value) {
    this._options.style = value;
    this._sync();
  }
  get title() {
    return this._options.title;
  }
  set title(value) {
    this._options.title = value;
    this._sync();
  }
  get message() {
    return this._options.message;
  }
  set message(value) {
    this._options.message = value;
    this._sync();
  }
  get primaryAction() {
    return this._options.primaryAction;
  }
  set primaryAction(value) {
    this._options.primaryAction = value;
    this._sync();
  }
  get secondaryAction() {
    return this._options.secondaryAction;
  }
  set secondaryAction(value) {
    this._options.secondaryAction = value;
    this._sync();
  }

  async show() {
    this._id = await hostCall("feedback", "showToast", [this._serialize()]);
    return this;
  }

  async hide() {
    if (this._id === null) return;
    await hostCall("feedback", "hideToast", [this._id]);
    this._id = null;
  }

  _sync() {
    if (this._id === null) return;
    hostCall("feedback", "updateToast", [this._id, this._serialize()]).catch(() => {});
  }

  /// Toast actions carry callbacks, which can't cross the bridge. Register them locally and send only
  /// the titles plus a token Swift echoes back through `runToastAction`.
  _serialize() {
    const encode = (action, slotName) => {
      if (!action) return null;
      const token = `${this._token()}:${slotName}`;
      toastActions.set(token, action.onAction);
      return { title: action.title, shortcut: action.shortcut, token };
    };
    return {
      style: this._options.style,
      title: this._options.title,
      message: this._options.message,
      primaryAction: encode(this._options.primaryAction, "primary"),
      secondaryAction: encode(this._options.secondaryAction, "secondary"),
    };
  }

  _token() {
    if (!this._tokenBase) this._tokenBase = `toast-${nextToastToken++}`;
    return this._tokenBase;
  }
}

Toast.Style = ToastStyle;

let nextToastToken = 1;
const toastActions = new Map();

export function runToastAction(token) {
  const handler = toastActions.get(token);
  if (!handler) return;
  // Raycast hands the live Toast to the callback; the shim passes the token holder's own toast.
  handler({ hide: () => {} });
}

export async function showToast(optionsOrStyle, title, message) {
  const options =
    typeof optionsOrStyle === "object" && optionsOrStyle !== null
      ? optionsOrStyle
      : { style: optionsOrStyle, title, message };
  const toast = new Toast(options);
  await toast.show();
  return toast;
}

export function showHUD(title, options = {}) {
  return hostCall("feedback", "showHUD", [String(title), options]);
}

export function confirmAlert(options = {}) {
  return hostCall("feedback", "confirmAlert", [
    {
      title: options.title,
      message: options.message,
      icon: options.icon,
      primaryAction: options.primaryAction ? { title: options.primaryAction.title, style: options.primaryAction.style } : null,
      dismissAction: options.dismissAction ? { title: options.dismissAction.title, style: options.dismissAction.style } : null,
      rememberUserChoice: !!options.rememberUserChoice,
    },
  ]).then((confirmed) => {
    if (confirmed) options.primaryAction?.onAction?.();
    else options.dismissAction?.onAction?.();
    return confirmed;
  });
}

// ─── Deprecated aliases still used by older extensions ──────────────

export const copyTextToClipboard = Clipboard.copy;
export const pasteText = Clipboard.paste;
export const clearClipboard = Clipboard.clear;
export const getLocalStorageItem = LocalStorage.getItem;
export const setLocalStorageItem = LocalStorage.setItem;
export const removeLocalStorageItem = LocalStorage.removeItem;
export const allLocalStorageItems = LocalStorage.allItems;
export const clearLocalStorage = LocalStorage.clear;
export const randomId = () => `${Date.now().toString(36)}${Math.floor(Math.random() * 1e9).toString(36)}`;
