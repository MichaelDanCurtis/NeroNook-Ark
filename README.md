**October 19 · local 0.4.3:** Nearly Nothing refinement: softer shared glass and controls, compact fit review and paired Light/Dark. Local package installed; visual checks do not imply fresh audio, device or network acceptance. [Evidence and limits](../NeroNook/reports/nearly-nothing-refinement-2026-10-18/README.md). No public update.

**October 18 · local 0.4.2 installed:** shared glass, paired Light/Dark, independent bundled presence/particle artwork and component motion. Saved connection/settings remain scoped to this plugin. [Rollout evidence and limits](../NeroNook/reports/redesign-ember-2026-10-18/README.md). No public release.

**October 17–18 · local 0.4.1 installed:** Recovered polls clear only their transient warning; command and pairing notices survive. 25 tests, signed package/process checks and actual Light/Dark refresh pass. Settings stay byte-identical; source following stays Off. [Evidence and limits](reports/rough-edges-2026-10-17/README.md). No public update.

**October 14 · 0.4.0 installed:** the primary card adds configurable keyboard-channel inputs, one-shot Test, owner verification and explicit source following through permitted SDK events. Default mapping is 1 → HDMI 1, 2 → DisplayPort, 3 → HDMI 2. Following is Off pending physical verification; commands are unacknowledged. [Delivery evidence](reports/easy-switch-2026-10-14/README.md).

# Ark 0.3.0 volume integration

Ark can now handle Mac volume keys and Nero's volume display through the generic `volume-v1` SDK. Install host 0.24.0 or later, then choose Odyssey Ark in NeroNook Settings → HUD → Volume control while the Ark audio output is selected. Enable Replace system HUD and give NeroNook macOS Accessibility access for media keys. Other outputs retain their own controls; this does not add a native macOS Sound slider.

The plugin resolves adjustments and mute toggles against fresh monitor readings, performs one setting write and returns confirmed state. Gestures expire before a delayed write; repeated requests are refused and busy gestures do not queue. Mute remains separate from volume. The plugin's standalone controls and older-host dashboard remain available without this optional interface. No helper app or Samsung code was added to the host.

# Odyssey Ark module for NeroNook

Independent native macOS plugin, version 0.2.0. Talks directly to a selected Odyssey Ark over the local network, with no companion application, installed CLI, Python runtime, cloud account, or separately running service. Requires macOS 14+ and NeroNook 0.23.0 (verified).

## Included

- Interactive sound and remote controls within the host’s 16:9 module stage, plus a single status line. The same plugin-owned HTML/SVG view runs in the Nook and the independent window; setup is behind the gear, not a Connection tab.
- Volume slider applies on release, an exact volume field has Set/Return, single-step buttons read fresh volume, and Sound on / Muted buttons apply explicit mute state. Only confirmed monitor readings become live state.
- Local SSDP discovery, manual IPv4 entry, Samsung Ark model verification and saved monitor identity.
- HTTP identity/status and UPnP RenderingControl volume/mute. The device's advertised action list gates controls; each setting verifies the selected identity and reads the result back.
- Samsung encrypted local WebSocket pairing and remote navigation, pinned to an explicitly approved monitor certificate. Pairing token is private to this plugin's Keychain entry. Remote key delivery has no per-key device acknowledgement and is labeled accordingly.
- Shared SDK `read_status`, `set_volume` and `set_mute` actions, with exact device targets and host review for changes. Read status and the status channel now include optional numeric volume, mute state and write-capability flags.
- Bounded network responses, no HTTP redirects, explicit unsupported states, no automatic command replay.

Direct brightness, contrast, picture mode, input assignment, KVM and Multi View APIs have not been exposed by the verified HTTP service. Remote Settings/Sources open the monitor's menus; they are not direct setting APIs. No power/factory/service-menu commands are included.

## Setup

Build with `swift test` and `bash scripts/package.sh`, using `NERONOOK_SIGNING_IDENTITY` for stable signing. Install `build/Ark Module.app` through NeroNook Settings → Modules. Open the gear, Find monitor or enter its IP, then Connect. If macOS asks, approve Local Network for Ark Module. Pair remote separately and approve NeroNook Ark on the physical monitor.

HTTP status and UPnP audio communication are unencrypted and intended for a trusted local network. Remote pairing uses encrypted port 8002. On first connection, review and explicitly approve the monitor certificate fingerprint; subsequent connections require that exact certificate. A changed certificate stops the connection and requires fresh review. There is no plaintext remote fallback or blanket certificate trust. Only private IPv4 destinations are accepted. No browser/session credentials are imported. Tokens are never included in plugin snapshots or logs. The package does not change the monitor's network/security settings.

The settings JSON is owned by `cafe.nero.plugin.ark` under `NeroNookPlugins`; the separate Keychain service is `cafe.nero.plugin.ark.remote`. Uninstalling NeroNook is not required to remove this module.

## Protocol evidence

The tested monitor's `/api/v2/` identifies LS55CG970NNXGO, Tizen, 3840×2160 and remote availability. Its `/dmr` descriptor on port 9197 advertises RenderingControl and same-host service paths. The service descriptor exposes Get/SetVolume and Get/SetMute. Other Samsung ports/models remain an explicit compatibility boundary.

References: [Samsung network protocol reference implementation](https://github.com/xchwarze/samsung-tv-ws-api), [Samsung remote key reference](https://github.com/xchwarze/samsung-tv-ws-api/blob/master/COMMANDS.md). This implementation is independently authored in Swift; no Python library or proprietary Samsung assets are bundled. Shared SDK snapshot is vendored from NeroNook 0.23.0 with exact hashes in SDK-SNAPSHOT.json. See STATUS.md for live acceptance.

## Interaction and verification

Background reads refresh every four seconds while the Nook or independent window is visible, and every thirty seconds otherwise. A user command cancels and invalidates any older poll; a delayed response cannot overwrite its result. Controls do not queue or replay commands. A removed/changed monitor, unavailable control or failed read-back disables audio until a new successful reading. Relative one-step changes resolve against a fresh reading, with values clamped to 0–100. Concurrent physical changes between HTTP reads/writes are not atomic.

`swift test` includes parsing, identity, capability, TLS pinning, one-write/read-back, relative volume, exact view-target and delayed-refresh regression tests. `python3 scripts/test-protocol.py` checks the independent package handshake and invalid action refusal using read-only live requests. Native and in-Nook acceptance is recorded separately in STATUS.md.

The remote must be connected explicitly after a module restart; its saved token and approved certificate can be reused. The main view shows connecting/error state. Its Home/Settings/Sources buttons operate menus on the physical monitor, not a mirrored Tizen screen or direct HDMI assignment.

## Remaining monitor integration

Mac volume keys and Nero’s volume HUD need a generic selectable audio endpoint in the shared SDK. Native macOS Sound-slider integration is a separate CoreAudio feasibility question. Brightness, direct input and Eclipse Lighting need separately verified transports. The September 24 live descriptors expose RenderingControl audio and DLNA media actions, but no direct brightness/input/lighting actions. No DDC write, input change or power command was tested here. [Samsung’s specification sheet](https://image-us.samsung.com/SamsungUS/home/computing/monitors/gaming/ls55cg970nnxgo/SPECSHEET_LS55CG970NNXGO_v2.pdf) establishes product features, not network control availability.
