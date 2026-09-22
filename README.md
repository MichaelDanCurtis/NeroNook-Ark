# Odyssey Ark module for NeroNook

Independent native macOS plugin. Talks directly to a selected Odyssey Ark over the local network, with no companion application, installed CLI, Python runtime, cloud account, or separately running service. Requires macOS 14+ and NeroNook 0.12.0+.

## Included

- Original 16:9 monitor dashboard and one-line status.
- Local SSDP discovery, manual IPv4 entry, Samsung Ark model verification and saved monitor identity.
- HTTP identity/status and UPnP RenderingControl volume/mute. The device's advertised action list gates controls; each setting verifies the selected identity and reads the result back.
- Samsung encrypted local WebSocket pairing and remote navigation, pinned to an explicitly approved monitor certificate. Pairing token is private to this plugin's Keychain entry. Remote key delivery has no per-key device acknowledgement and is labeled accordingly.
- Shared SDK `read_status`, `set_volume` and `set_mute` actions, with exact device targets and host review for changes.
- Bounded network responses, no HTTP redirects, explicit unsupported states, no automatic command replay.

Direct brightness, contrast, picture mode, input assignment, KVM and Multi View APIs have not been exposed by the verified HTTP service. Remote Settings/Sources open the monitor's menus; they are not direct setting APIs. No power/factory/service-menu commands are included.

## Setup

Build with `swift test` and `bash scripts/package.sh`, using `NERONOOK_SIGNING_IDENTITY` for stable signing. Install `build/Ark Module.app` through NeroNook Settings → Modules. Open Monitor controls, Find monitor or enter its IP, then Connect. If macOS asks, approve Local Network for Ark Module. Pair remote separately and approve NeroNook Ark on the physical monitor.

HTTP status and UPnP audio communication are unencrypted and intended for a trusted local network. Remote pairing uses encrypted port 8002. On first connection, review and explicitly approve the monitor certificate fingerprint; subsequent connections require that exact certificate. A changed certificate stops the connection and requires fresh review. There is no plaintext remote fallback or blanket certificate trust. Only private IPv4 destinations are accepted. No browser/session credentials are imported. Tokens are never included in plugin snapshots or logs. The package does not change the monitor's network/security settings.

The settings JSON is owned by `cafe.nero.plugin.ark` under `NeroNookPlugins`; the separate Keychain service is `cafe.nero.plugin.ark.remote`. Uninstalling NeroNook is not required to remove this module.

## Protocol evidence

The tested monitor's `/api/v2/` identifies LS55CG970NNXGO, Tizen, 3840×2160 and remote availability. Its `/dmr` descriptor on port 9197 advertises RenderingControl and same-host service paths. The service descriptor exposes Get/SetVolume and Get/SetMute. Other Samsung ports/models remain an explicit compatibility boundary.

References: [Samsung network protocol reference implementation](https://github.com/xchwarze/samsung-tv-ws-api), [Samsung remote key reference](https://github.com/xchwarze/samsung-tv-ws-api/blob/master/COMMANDS.md). This implementation is independently authored in Swift; no Python library or proprietary Samsung assets are bundled. Shared SDK snapshot is vendored from NeroNook commit eaa9196b828309e01aaa798bfce820c83012181a. See STATUS.md for live acceptance.
