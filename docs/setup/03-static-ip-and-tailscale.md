# 03 — Static LAN IP + Tailscale (run on the Debian 13 server)

1. Reserve a static LAN IP: in your router's DHCP settings, bind the server's MAC to a
   fixed address (e.g. 192.168.1.50). Confirm with `ip a`.
2. Install Tailscale: `curl -fsSL https://tailscale.com/install.sh | sh`
3. `sudo tailscale up` and authenticate (free personal plan).
4. Note the MagicDNS name (`tailscale status`) — e.g. `immich-server.tailXXXX.ts.net`.
5. On each phone: install the Tailscale app, sign in to the same account, set always-on.
6. No router port-forwarding. Do NOT expose 2283 to the internet.
