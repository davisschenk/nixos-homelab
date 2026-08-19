output "estuary_ipv4" {
  description = "Public IPv4 address assigned to estuary."
  value       = local.estuary_ipv4
}

output "estuary_wireguard_endpoint" {
  description = "Public WireGuard endpoint used by mangrove and CI."
  value       = "${local.estuary_ipv4}:${var.wireguard_port}"
}

output "bootstrap_complete" {
  description = "Whether public bootstrap SSH has been removed."
  value       = var.bootstrap_complete
}

output "monthly_base_price_usd" {
  description = "Live OVH catalog price for the selected one-month VPS-1 plan."
  value       = local.monthly_price_usd
}
