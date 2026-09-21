# Custom MCP hosting

Mangrove can run custom MCP servers as OCI containers and publish each one through
the existing Cloudflare Tunnel and Caddy wildcard. Servers must expose the MCP
Streamable HTTP transport; the conventional endpoint is `/mcp`.

Each server receives its own root-level hostname because the Cloudflare certificate
covers `*.schenkenberger.dev`, not nested wildcard names. All container ports bind
only to loopback, and Caddy requires the shared SOPS-managed bearer token before a
request reaches a server. Caddy strips that credential before proxying so a custom
server cannot reuse it to call other hosted servers.

## Add a server

Build and publish the server as an OCI image, then add it to
`mylab.mcp.servers` on Mangrove:

```nix
mylab.mcp.servers.inventory = {
  image = "ghcr.io/davisschenk/inventory-mcp:1.0.0";
  hostPort = 8100;
  containerPort = 8000;
  environment = {
    MCP_TRANSPORT = "streamable-http";
    MCP_HOST = "0.0.0.0";
    MCP_PORT = "8000";
  };
};
```

This publishes `https://mcp-inventory.schenkenberger.dev/mcp`. The server name,
host port, and hostname must be unique. Pin production images to a version or
digest rather than `latest`.

For server-specific credentials, create a separate SOPS template and pass its path
through `environmentFiles`. Persist state by adding a bind mount to `volumes` and
the corresponding directory under `environment.persistence."/persist"`.

## Connect a client

Read the shared token with `just view mcp`, store it in the client's secret store or
environment, and configure an `Authorization: Bearer <token>` header. For Codex CLI:

```toml
[mcp_servers.inventory]
url = "https://mcp-inventory.schenkenberger.dev/mcp"
bearer_token_env_var = "HOMELAB_MCP_TOKEN"
```

The token authenticates access to the hosting boundary. A server that exposes
tools with different privilege levels should still enforce authorization inside
the server.

## Rotate the shared token

Run `just edit mcp`, replace `mcp_bearer_token`, and deploy normally. SOPS restarts
the verifier when the decrypted secret changes. Clients must be updated with the
new token before they reconnect.
