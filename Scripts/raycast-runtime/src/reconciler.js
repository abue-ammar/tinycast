// A React host renderer whose "DOM" is a plain JSON tree that Swift renders natively.
//
// Two conventions make the Raycast component surface expressible:
//   * `__slot` instances fold their children into the parent's props under a name, so element-valued
//     props (`actions={<ActionPanel/>}`, `detail={<List.Item.Detail/>}`) reach Swift as structure.
//   * function props become `{"$fn": "<nodeId>:<propName>"}` handles; Swift dispatches them back by id.

import Reconciler from "react-reconciler";
import { DefaultEventPriority } from "react-reconciler/constants";
import { reportUncaught } from "./polyfills.js";

export const SLOT_TYPE = "__slot";

let nextInstanceId = 1;

function createNode(type, props) {
  return { id: nextInstanceId++, type, props: props ?? {}, children: [] };
}

const hostConfig = {
  supportsMutation: true,
  supportsPersistence: false,
  supportsHydration: false,
  isPrimaryRenderer: true,
  noTimeout: -1,
  warnsIfNotActing: false,

  getRootHostContext: () => null,
  getChildHostContext: (parentContext) => parentContext,
  getPublicInstance: (instance) => instance,

  createInstance: (type, props) => createNode(type, props),
  createTextInstance: (text) => ({ id: nextInstanceId++, type: "#text", text, children: [] }),

  appendInitialChild: (parent, child) => parent.children.push(child),
  appendChild: (parent, child) => {
    detach(parent, child);
    parent.children.push(child);
  },
  appendChildToContainer: (container, child) => {
    detach(container, child);
    container.children.push(child);
  },
  insertBefore: (parent, child, before) => insert(parent, child, before),
  insertInContainerBefore: (container, child, before) => insert(container, child, before),
  removeChild: (parent, child) => detach(parent, child),
  removeChildFromContainer: (container, child) => detach(container, child),
  clearContainer: (container) => {
    container.children.length = 0;
  },

  finalizeInitialChildren: () => false,
  shouldSetTextContent: () => false,
  commitUpdate: (instance, type, prevProps, nextProps) => {
    instance.props = nextProps;
  },
  commitTextUpdate: (instance, prev, next) => {
    instance.text = next;
  },
  commitMount: () => {},
  resetTextContent: () => {},

  prepareForCommit: () => null,
  resetAfterCommit: (container) => container.onCommit(),
  preparePortalMount: () => {},
  detachDeletedInstance: () => {},

  scheduleTimeout: (fn, delay) => setTimeout(fn, delay),
  cancelTimeout: (handle) => clearTimeout(handle),

  // React 19 update-priority hooks: a single-surface renderer has no event lanes to distinguish.
  getCurrentUpdatePriority: () => DefaultEventPriority,
  setCurrentUpdatePriority: () => {},
  resolveUpdatePriority: () => DefaultEventPriority,
  getCurrentEventPriority: () => DefaultEventPriority,
  shouldAttemptEagerTransition: () => false,
  requestPostPaintCallback: () => {},
  trackSchedulerEvent: () => {},
  resolveEventType: () => null,
  resolveEventTimeStamp: () => -1.1,
  maySuspendCommit: () => false,
  preloadInstance: () => true,
  startSuspendingCommit: () => {},
  suspendInstance: () => {},
  waitForCommitToBeReady: () => null,
  NotPendingTransition: null,
  HostTransitionContext: {
    $$typeof: Symbol.for("react.context"),
    Provider: null,
    Consumer: null,
    _currentValue: null,
    _currentValue2: null,
    _threadCount: 0,
  },
  resetFormInstance: () => {},
  bindToConsole: (method, args) => () => method.apply(console, args),

  beforeActiveInstanceBlur: () => {},
  afterActiveInstanceBlur: () => {},
  prepareScopeUpdate: () => {},
  getInstanceFromScope: () => null,
  getInstanceFromNode: () => null,
};

function detach(parent, child) {
  const index = parent.children.indexOf(child);
  if (index >= 0) parent.children.splice(index, 1);
}

function insert(parent, child, before) {
  detach(parent, child);
  const index = parent.children.indexOf(before);
  if (index < 0) parent.children.push(child);
  else parent.children.splice(index, 0, child);
}

const reconciler = Reconciler(hostConfig);

/// One mounted command. `onTree` fires after every commit with the serialized tree; handler lookups
/// go through `handlers`, which is rebuilt on each serialization so a dispatch always hits the
/// callback from the newest render.
export class Surface {
  constructor(onTree, onError) {
    this.handlers = new Map();
    this.onTree = onTree;
    this.onError = onError;
    this.container = { id: 0, type: "#root", props: {}, children: [], onCommit: () => this.flush() };
    this.root = reconciler.createContainer(
      this.container,
      0, // LegacyRoot — extensions never opt into concurrent-only behaviour
      null,
      false,
      null,
      "tinycast",
      (error) => this.onError(error),
      (error) => this.onError(error),
      (error) => this.onError(error),
      null,
    );
  }

  render(element) {
    reconciler.updateContainer(element, this.root, null, null);
  }

  unmount() {
    try {
      reconciler.updateContainer(null, this.root, null, null);
    } catch (error) {
      reportUncaught(error);
    }
    this.handlers.clear();
  }

  flush() {
    this.handlers.clear();
    const children = this.container.children.map((child) => this.serialize(child)).filter(Boolean);
    this.onTree({ children });
  }

  dispatch(handlerId, args) {
    const handler = this.handlers.get(handlerId);
    if (!handler) return false;
    handler(...args);
    return true;
  }

  serialize(node) {
    if (node.type === "#text") return { type: "#text", text: String(node.text) };

    const props = {};
    for (const key of Object.keys(node.props)) {
      if (key === "children") continue;
      const value = this.encode(node.props[key], node.id, key);
      if (value !== undefined) props[key] = value;
    }

    const children = [];
    for (const child of node.children) {
      // A slot child is structure for the parent, not a row of its own.
      if (child.type === SLOT_TYPE) {
        const name = child.props?.name;
        if (!name) continue;
        const contents = child.children.map((entry) => this.serialize(entry)).filter(Boolean);
        if (contents.length) props[name] = child.props.single ? contents[0] : contents;
        continue;
      }
      const serialized = this.serialize(child);
      if (serialized) children.push(serialized);
    }

    return { id: node.id, type: node.type, props, children };
  }

  /// JSON-safe encoding of a prop value. Functions become dispatchable handles; Dates keep their
  /// type so Swift can round-trip a Form.DatePicker value.
  encode(value, nodeId, key) {
    if (value === undefined || value === null) return value === null ? null : undefined;
    switch (typeof value) {
      case "function": {
        const handlerId = `${nodeId}:${key}`;
        this.handlers.set(handlerId, value);
        return { $fn: handlerId };
      }
      case "string":
      case "number":
      case "boolean":
        return value;
      case "bigint":
        return Number(value);
      case "symbol":
        return undefined;
      default:
        break;
    }
    if (value instanceof Date) return { $date: value.toISOString() };
    if (Array.isArray(value)) {
      return value.map((item, index) => this.encode(item, nodeId, `${key}.${index}`) ?? null);
    }
    // A React element that reached us as a plain prop (rather than through a slot) can't be
    // rendered; drop it instead of serializing React internals.
    if (value.$$typeof) return undefined;
    const out = {};
    for (const name of Object.keys(value)) {
      const encoded = this.encode(value[name], nodeId, `${key}.${name}`);
      if (encoded !== undefined) out[name] = encoded;
    }
    return out;
  }
}

export function flushSync(fn) {
  return reconciler.flushSyncWork ? reconciler.flushSyncWork(fn) : fn?.();
}

export function actBatch(fn) {
  return fn();
}
