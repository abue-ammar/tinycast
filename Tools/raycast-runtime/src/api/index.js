// Assembles the module an extension gets from `require("@raycast/api")`.

import { Action, ActionPanel, Detail, Form, Grid, List, MenuBarExtra, Navigation, setActionEffects, useNavigation } from "./components.js";
import * as enums from "./enums.generated.js";
import * as system from "./system.js";

const { nestedEnums, ...flatEnums } = enums;

Form.DatePicker.Type = flatEnums.DatePickerType;
Action.PickDate.Type = flatEnums.DatePickerType;
Grid.Fit = flatEnums.GridFit;
Grid.Inset = flatEnums.GridInset;
Grid.ItemSize = flatEnums.GridItemSize;
Grid.AspectRatio = flatEnums.GridAspectRatio;
Action.Style = flatEnums.ActionStyle;

// The convenience actions run their effect through the system APIs rather than duplicating them.
setActionEffects({
  copy: async ({ content, concealed }) => {
    await system.Clipboard.copy(content, { concealed });
    await system.closeMainWindow();
    await system.showHUD("Copied to Clipboard");
  },
  paste: async ({ content }) => {
    await system.Clipboard.paste(content);
  },
  open: async ({ target, application }) => {
    await system.open(target, application);
    await system.closeMainWindow();
  },
  openWith: async ({ path }) => {
    await system.openWith(path);
  },
  showInFinder: async ({ path }) => {
    await system.showInFinder(path);
    await system.closeMainWindow();
  },
  trash: async ({ paths }) => {
    await system.trash(paths);
  },
  createSnippet: () => system.unsupported("Action.CreateSnippet"),
  createQuicklink: () => system.unsupported("Action.CreateQuicklink"),
  quickLook: () => system.unsupported("Action.ToggleQuickLook"),
  unsupported: (what) => system.unsupported(what),
});

const Image = { Mask: nestedEnums.Image.Mask };

const Alert = { ActionStyle: nestedEnums.Alert.ActionStyle };

const Keyboard = {
  Shortcut: {
    Common: {
      Copy: { modifiers: ["cmd", "shift"], key: "c" },
      CopyDeeplink: { modifiers: ["cmd", "shift"], key: "c" },
      CopyName: { modifiers: ["cmd", "shift"], key: "." },
      CopyPath: { modifiers: ["cmd", "shift"], key: "," },
      Save: { modifiers: ["cmd"], key: "s" },
      Duplicate: { modifiers: ["cmd"], key: "d" },
      Edit: { modifiers: ["cmd"], key: "e" },
      MoveDown: { modifiers: ["cmd", "shift"], key: "arrowDown" },
      MoveUp: { modifiers: ["cmd", "shift"], key: "arrowUp" },
      New: { modifiers: ["cmd"], key: "n" },
      Open: { modifiers: ["cmd"], key: "o" },
      OpenWith: { modifiers: ["cmd", "shift"], key: "o" },
      Pin: { modifiers: ["cmd", "shift"], key: "p" },
      Refresh: { modifiers: ["cmd"], key: "r" },
      Remove: { modifiers: ["ctrl"], key: "x" },
      RemoveAll: { modifiers: ["ctrl", "shift"], key: "x" },
      ToggleQuickLook: { modifiers: ["cmd"], key: "y" },
    },
  },
};

/// Surfaces Tinycast doesn't implement. They exist so a bundle that merely imports them still loads;
/// calling one gives the extension (and the user) a clear reason instead of a TypeError.
function rejectingNamespace(name, members) {
  const target = {};
  for (const member of members) target[member] = () => system.unsupported(`${name}.${member}`);
  return target;
}

const AI = {
  ...rejectingNamespace("AI", ["ask"]),
  Model: Object.freeze({}),
  Creativity: Object.freeze({}),
};

const OAuth = {
  RedirectMethod: nestedEnums.OAuth.RedirectMethod,
  PKCEClient: class PKCEClient {
    constructor() {
      throw new Error("OAuth.PKCEClient is not supported in Tinycast extensions yet. See docs/extensions.md.");
    }
  },
};

const BrowserExtension = rejectingNamespace("BrowserExtension", ["getContent", "getTabs"]);

const WindowManagement = {
  DesktopType: nestedEnums.WindowManagement.DesktopType,
  ...rejectingNamespace("WindowManagement", ["getWindowsOnActiveDesktop", "getActiveWindow", "setWindowBounds", "getDesktops"]),
};

export const raycastApi = {
  // Components
  List,
  Grid,
  Detail,
  Form,
  ActionPanel,
  Action,
  MenuBarExtra,
  Icon: flatEnums.Icon,
  Color: flatEnums.Color,
  Image,
  Keyboard,
  Alert,
  Toast: system.Toast,
  Cache: system.Cache,
  LaunchType: flatEnums.LaunchType,
  PopToRootType: flatEnums.PopToRootType,

  // Navigation
  useNavigation,
  Navigation,

  // Feedback
  showToast: system.showToast,
  showHUD: system.showHUD,
  confirmAlert: system.confirmAlert,

  // System
  Clipboard: system.Clipboard,
  LocalStorage: system.LocalStorage,
  environment: system.environment,
  getPreferenceValues: system.getPreferenceValues,
  openExtensionPreferences: system.openExtensionPreferences,
  openCommandPreferences: system.openCommandPreferences,
  closeMainWindow: system.closeMainWindow,
  popToRoot: system.popToRoot,
  clearSearchBar: system.clearSearchBar,
  open: system.open,
  trash: system.trash,
  showInFinder: system.showInFinder,
  getApplications: system.getApplications,
  getDefaultApplication: system.getDefaultApplication,
  getFrontmostApplication: system.getFrontmostApplication,
  getSelectedText: system.getSelectedText,
  getSelectedFinderItems: system.getSelectedFinderItems,
  getFrontmostBrowserTab: system.getFrontmostBrowserTab,
  captureException: system.captureException,
  launchCommand: system.launchCommand,
  updateCommandMetadata: system.updateCommandMetadata,

  // Unimplemented namespaces
  AI,
  OAuth,
  BrowserExtension,
  WindowManagement,

  // Deprecated aliases
  copyTextToClipboard: system.copyTextToClipboard,
  pasteText: system.pasteText,
  clearClipboard: system.clearClipboard,
  getLocalStorageItem: system.getLocalStorageItem,
  setLocalStorageItem: system.setLocalStorageItem,
  removeLocalStorageItem: system.removeLocalStorageItem,
  allLocalStorageItems: system.allLocalStorageItems,
  clearLocalStorage: system.clearLocalStorage,
  randomId: system.randomId,
  ActionPanelItem: Action,
  ActionPanelSection: ActionPanel.Section,
  ActionPanelSubmenu: ActionPanel.Submenu,
  CopyToClipboardAction: Action.CopyToClipboard,
  OpenInBrowserAction: Action.OpenInBrowser,
  OpenAction: Action.Open,
  PasteAction: Action.Paste,
  PushAction: Action.Push,
  ShowInFinderAction: Action.ShowInFinder,
  SubmitFormAction: Action.SubmitForm,
  TrashAction: Action.Trash,
  ImageMask: Image.Mask,
  ToastStyle: system.Toast.Style,
  AlertActionStyle: Alert.ActionStyle,
  FormTextField: Form.TextField,
  FormTextArea: Form.TextArea,
  FormCheckbox: Form.Checkbox,
  FormDatePicker: Form.DatePicker,
  FormDropdown: Form.Dropdown,
  FormDropdownItem: Form.Dropdown.Item,
  FormDropdownSection: Form.Dropdown.Section,
  FormSeparator: Form.Separator,
  FormTagPicker: Form.TagPicker,
  FormTagPickerItem: Form.TagPicker.Item,
};

// Bundles compiled by esbuild reach for the interop marker before spreading the namespace.
raycastApi.__esModule = true;
raycastApi.default = raycastApi;
