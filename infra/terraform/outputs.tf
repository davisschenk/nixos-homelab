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
  value       = local.monthly_base_price_usd
}

output "monthly_required_options_price_usd" {
  description = "Live OVH catalog price for the required local storage and standard backup options."
  value       = local.monthly_required_options_price_usd
}

output "monthly_total_price_usd" {
  description = "Combined recurring monthly price for the VPS and all required options."
  value       = local.monthly_total_price_usd
}

output "required_plan_options" {
  description = "OVH plan option codes explicitly included in the VPS order."
  value       = local.required_plan_option_codes
}
