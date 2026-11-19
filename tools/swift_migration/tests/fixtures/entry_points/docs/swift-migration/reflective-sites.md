# Reflective-site registry

A fixture copy of a few rows of the real registry, in its shape.

## 1. What this is and how to use it

Text.

## 2. Summary

### Names that must be preserved

The rule: text.

| Name | Resolves | Runtime name | Note | Sites |
|---|---|---|---|---|
| `contextMenuAction*` | 1 selectors with prefix |  | selector prefix pattern (Widget.m:1) | sources/Widget.m:1 |
| `iTermThingMO` | class | `iTermThingMO` | persisted by name | sources/Widget.m:70 |
| `iTermWidget +load_*` | 0 class methods with prefix |  |  | sources/Widget.m:2 |
| `iTermWidget.fooBar` | property |  |  | sources/Widget.m:26 |
| `stringPerformed` | selector |  |  | sources/Widget.m:23 |

Not listed by name: text.

## 3. Dynamic sites

Grouped by mechanism.

### Calling by selector

#### `ThirdParty/PSMTabBarControl/PSM.m`

- `ThirdParty/PSMTabBarControl/PSM.m:8` in `PSMDynamic`: `NSSelectorFromString` on `name`
- `ThirdParty/PSMTabBarControl/PSM.m:8` in `PSMDynamic`: `performSelector:` on `NSSelectorFromString(name)`

  **OPEN-INTERNAL.** Performs any selector named by its caller on any object.

  Names: none.

#### `sources/Widget.m`

- `sources/Widget.m:23` in `-[iTermWidget go]`: `NSSelectorFromString` on `@"stringPerformed"`

  **CLOSED.** A literal. Reach: `stringPerformed`.

  Names: `stringPerformed`.

## 4. Callers of generic helpers

None.

## 5. Selector and class names used as data

- `sources/Widget.m:1` in `-[iTermWidget validateMenuItem:]`: `hasPrefix:@"contextMenuAction"`

  **CLOSED.** Enabled by prefix.

  Names: `contextMenuAction*`.

- `sources/Widget.m:26` in `-[iTermWidget go]`: `setValue:forKey:@"fooBar"`

  **CLOSED.** A key.

  Names: `iTermWidget.fooBar`, `iTermWidget +load_*`.

## 6. Names persisted or sent between processes by the frameworks

### Keyed archives

- `sources/Widget.m:70`: archived thing

  **OPEN-EXTERNAL.** Saved by name.

  Names: `iTermThingMO`.

## 7. OPEN-EXTERNAL sites without an allowlist

None.

## 9. Known gaps

None.

#### `sources/SDKUsers.m`

- `sources/SDKUsers.m:71` in `-[iTermScriptingWindow methodSignatureForSelector:]`: `methodSignatureForSelector:` on `selector`

  **GENERIC.** Forwards every message to the window it wraps.

  Names: none.
