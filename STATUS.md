# Ark module 0.1.0 acceptance

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
