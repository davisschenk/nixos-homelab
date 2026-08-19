variable "bootstrap_complete" {
  description = "Close public bootstrap SSH and enable GitOps deployment when true."
  type        = bool
  default     = false
}

variable "bootstrap_ssh_cidr" {
  description = "Public IPv4 CIDR allowed to reach Debian SSH during bootstrap."
  type        = string
  default     = ""
}

variable "cloudflare_zone" {
  description = "Cloudflare zone containing the game record."
  type        = string
  default     = "schenkenberger.dev"
}

variable "wireguard_port" {
  description = "Public WireGuard UDP port on estuary."
  type        = number
  default     = 51820

  validation {
    condition     = var.wireguard_port >= 1 && var.wireguard_port <= 65535
    error_message = "wireguard_port must be between 1 and 65535."
  }
}
