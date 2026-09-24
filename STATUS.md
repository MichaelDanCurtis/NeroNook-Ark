# Ark module 0.2.0 acceptance

September 24, 2026. Independently packaged and installed; host runtime remains 0.23.0.

## Main-screen controls

Replaced Monitor/Connection diagrams with one interactive view. Sound includes a release-to-set slider, exact volume entry with Set/Return, one-step adjustment buttons and explicit Sound on / Muted controls. The paired remote exposes Home, Sources menu, Settings menu, Back and navigation on the same screen. Connection details, certificate review and unavailable capabilities live behind the gear. Original vector monitor artwork is decorative, not a live monitor feed. The view scales against both available width and height and has no duplicate action row.

The shared SDK status now includes numeric volume, mute and capability flags; the existing exact-target reviewed actions remain. All vendor logic, transport, credentials and resources are inside this independent package. No companion application, helper server or host implementation was added.

## Verification

- 15 Swift tests pass: the existing nine plus relative-volume freshness/bounds, invalid-step refusal, same-value mute/read-back, stale view-target rejection and a delayed HTTP poll that cannot overwrite a confirmed command. The refresh test exercises the actual module coordinator against injected HTTP responses without hardware.
- Release packaging, strict signing, JavaScript syntax, SDK hash and read-only protocol checks pass. The harness validates the one custom panel, bounded state, single status line and invalid action refusal.
- Live read-only discovery confirms the saved LS55CG970NNXGO identity, Tizen, 3840×2160 and current RenderingControl actions. Volume/mute are advertised; direct brightness, input assignment and rear lighting are not. No DLNA media, power or source-change command was sent.
- Native window and built-in-display Nook were visually inspected. Volume 16 and sound on were read from the actual monitor. Set volume at the current 16 and Sound on at the current false mute state returned confirmed monitor read-back, both in the window and in the Nook.
- The encrypted remote reconnects from the saved Keychain token and existing certificate pin after plugin replacement; navigation buttons become enabled. No new certificate trust or permission was needed. Physical navigation/menu response remains unverified; no navigation keys were sent during this acceptance.
- A final feedback pass exposes Connecting and remote errors in the main view and prevents repeated pairing while a connection is pending. The installed final package visibly progressed from Connecting to Connected without another approval prompt; its executable, manifest and view assets match the signed build.
- The laptop's Logitech selection and unpinned hover behavior were restored after acceptance. The external display retains Bambu Monitor. Both Nooks were collapsed after the checks.

## Remaining

Physical remote and slider-drag interaction, external remote changes, idle/sleep/network recovery and other firmware/models remain separate acceptance items. Mac volume keys/Nero HUD should use a generic SDK audio endpoint next. Native macOS Sound-slider integration needs a separate CoreAudio assessment. Direct brightness/input/Eclipse Lighting still require capability investigation; they are not presented as working controls. No public release/notarization claim.

## Earlier 0.1.0 acceptance

September 22, 2026. Independent native Swift package at `/Volumes/Main External/Development/NeroNook-Ark`. No host implementation changes or companion application requirements.

## Verified

- Nine core tests pass: private addresses, exact monitor identity, bounded XML and advertised service paths, command validation, unsupported controls, one-write/read-back behavior, remote allowlist and explicit certificate pinning.
- SDK process harness passes handshake, original 16:9 snapshot, single status line and invalid action rejection without a device write.
- Release app builds, development signature verifies, and NeroNook's reviewed update installs successfully while preserving settings and monitor placement. Both displays have the module enabled.
- Local SSDP discovery identifies the actual Samsung monitor. HTTP `/api/v2/` confirms second-generation LS55CG970NNXGO, Tizen and 3840×2160. RenderingControl on port 9197 advertises Get/SetVolume and Get/SetMute.
- Native controls read real volume and mute. Same-value Apply volume (23) and Apply mute (off) were exercised; audio confirmation is backed by a post-write device read. Later live UI readings showed volume 32, with sound on.
- Port-8001 remote pairing was rejected. The installed implementation uses encrypted port 8002 with a user-approved exact certificate pin. The native UI and Nook dashboard both show Remote connected. The native UI also reports Settings sent; this is transport delivery, not a per-key device acknowledgement.
- Native settings and the Nook's Ark dashboard were visually inspected. The monitor diagram, live volume, remote state, side selector and one-line status fit the shared module presentation.

## Remaining acceptance

- Physical observation of remote menu/navigation behavior is pending the user's reply. Pairing persistence across process restart, sleep/wake and network changes remain untested. Commands are never replayed automatically.
- Brightness, contrast, picture modes, direct input assignment, KVM, Multi View and cockpit controls are not exposed by the verified HTTP service. Settings/Sources are remote menu keys, not direct setting APIs.
- No input or power change was sent during acceptance. No claim of full Ark feature parity, support for other firmware/models, clean-Mac install, notarization or public release.

## Ownership

All Samsung discovery, HTTP/UPnP, encrypted remote pairing, settings, Keychain handling and commands live in this package. The host only uses the existing generic SDK. Development tests use Python, but the shipped app has no Python or external runtime dependency. The vendored SDK is the sole package dependency.
