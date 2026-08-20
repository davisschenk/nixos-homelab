data "http" "ovh_vps_catalog" {
  url = "https://api.us.ovhcloud.com/1.0/order/catalog/public/vps?ovhSubsidiary=US"

  request_headers = {
    Accept = "application/json"
  }
}

locals {
  ingress = jsondecode(file("${path.module}/../ingress.json"))
  catalog = jsondecode(data.http.ovh_vps_catalog.response_body)

  vps1_plan_codes = sort(distinct([
    for plan in local.catalog.plans : plan.planCode
    if can(regex("^vps-[0-9]+-model1$", plan.planCode))
    && contains([for configuration in plan.configurations : configuration.name], "vps_datacenter")
    && contains(flatten([
      for configuration in plan.configurations : configuration.name == "vps_datacenter" ? configuration.values : []
    ]), "US-WEST-OR")
    && contains(flatten([
      for configuration in plan.configurations : configuration.name == "vps_os" ? configuration.values : []
    ]), "Debian 13")
  ]))

  vps1_plan_code = try(reverse(local.vps1_plan_codes)[0], "")
  vps1_plan      = try(one([for plan in local.catalog.plans : plan if plan.planCode == local.vps1_plan_code]), null)
  monthly_base_prices = local.vps1_plan == null ? [] : [
    for pricing in local.vps1_plan.pricings : pricing
    if pricing.mode == "default"
    && pricing.commitment == 0
    && pricing.interval == 1
    && pricing.intervalUnit == "month"
    && contains(pricing.capacities, "renew")
  ]
  monthly_base_price_usd = try(one(local.monthly_base_prices).price / 100000000, 999)

  mandatory_addon_families = local.vps1_plan == null ? [] : [
    for family in local.vps1_plan.addonFamilies : family
    if family.mandatory
  ]
  storage_option_codes = distinct(flatten([
    for family in local.mandatory_addon_families : family.addons
    if family.name == "storage"
  ]))
  backup_option_codes = distinct(flatten([
    for family in local.mandatory_addon_families : family.addons
    if family.name == "automatedBackup"
  ]))
  standard_backup_option_codes = [
    for addon in local.catalog.addons : addon.planCode
    if contains(local.backup_option_codes, addon.planCode)
    && strcontains(lower(addon.invoiceName), "standard")
  ]
  required_plan_option_codes = [
    try(one(local.storage_option_codes), ""),
    try(one(local.standard_backup_option_codes), ""),
  ]
  monthly_required_option_prices = [
    for option_code in local.required_plan_option_codes : [
      for pricing in try(one([
        for addon in local.catalog.addons : addon
        if addon.planCode == option_code
      ]).pricings, []) : pricing
      if pricing.mode == "default"
      && pricing.commitment == 0
      && pricing.interval == 1
      && pricing.intervalUnit == "month"
      && contains(pricing.capacities, "renew")
    ]
  ]
  monthly_required_options_price_usd = sum([
    for prices in local.monthly_required_option_prices :
    try(one(prices).price / 100000000, 999)
  ])
  monthly_total_price_usd = local.monthly_base_price_usd + local.monthly_required_options_price_usd
  vps1_catalog_valid = (
    local.vps1_plan != null
    && length(local.monthly_base_prices) == 1
    && toset([for family in local.mandatory_addon_families : family.name]) == toset([
      "os",
      "storage",
      "automatedBackup",
    ])
    && length(local.storage_option_codes) == 1
    && length(local.standard_backup_option_codes) == 1
    && alltrue([
      for prices in local.monthly_required_option_prices : length(prices) == 1
    ])
  )

  ingress_shape_valid = alltrue([
    for entry in local.ingress :
    toset(keys(entry)) == toset(["name", "protocol", "from", "to", "target"])
  ])
  ingress_values_valid = alltrue([
    for entry in local.ingress :
    contains(["tcp", "udp"], try(entry.protocol, ""))
    && try(entry.target, "") == "mangrove"
    && try(entry.from, 0) >= 1
    && try(entry.from, 0) <= try(entry.to, -1)
    && try(entry.to, 65536) <= 65535
  ])
  ingress_names_unique = length(distinct([for entry in local.ingress : entry.name])) == length(local.ingress)
  ingress_ranges_disjoint = alltrue(flatten([
    for left_index, left in local.ingress : [
      for right_index, right in local.ingress :
      left_index >= right_index
      || left.protocol != right.protocol
      || left.to < right.from
      || right.to < left.from
    ]
  ]))
  edge_rule_count_valid = length(local.ingress) <= 13
}

check "vps1_catalog" {
  assert {
    condition     = local.vps1_catalog_valid
    error_message = "The OVH US catalog does not contain one supported monthly VPS-1 order with the expected mandatory options in Hillsboro."
  }

  assert {
    condition     = local.monthly_total_price_usd < 10
    error_message = "The selected OVH VPS and its required options do not have a combined recurring price below USD 10."
  }
}

check "bootstrap_ssh" {
  assert {
    condition     = var.bootstrap_complete || can(cidrnetmask(var.bootstrap_ssh_cidr))
    error_message = "bootstrap_ssh_cidr must be a valid IPv4 CIDR until bootstrap_complete is true."
  }
}

check "ingress" {
  assert {
    condition     = local.ingress_shape_valid && local.ingress_values_valid && local.ingress_names_unique && local.ingress_ranges_disjoint && local.edge_rule_count_valid
    error_message = "infra/ingress.json contains an invalid, overlapping, or unknown ingress entry."
  }
}

resource "ovh_vps" "estuary" {
  display_name         = "estuary"
  do_not_send_password = false
  ovh_subsidiary       = "US"

  plan = [{
    duration     = "P1M"
    plan_code    = local.vps1_plan_code
    pricing_mode = "default"
    configuration = [
      {
        label = "vps_datacenter"
        value = "US-WEST-OR"
      },
      {
        label = "vps_os"
        value = "Debian 13"
      }
    ]
  }]

  plan_option = [
    for option_code in local.required_plan_option_codes : {
      duration     = "P1M"
      plan_code    = option_code
      pricing_mode = "default"
      quantity     = 1
    }
  ]

  lifecycle {
    prevent_destroy = true

    precondition {
      condition     = local.vps1_catalog_valid && local.monthly_total_price_usd < 10
      error_message = "Refusing to order an OVH VPS whose required options are invalid or whose combined recurring price is USD ${local.monthly_total_price_usd}."
    }
  }
}

data "ovh_vps" "estuary" {
  service_name = ovh_vps.estuary.name
}

locals {
  estuary_ipv4s = [
    for ip in data.ovh_vps.estuary.ips : split("/", ip)[0]
    if !strcontains(ip, ":")
  ]
  estuary_ipv4     = one(local.estuary_ipv4s)
  estuary_cidr     = "${local.estuary_ipv4}/32"
  ingress_rule_end = length(local.ingress) + 2

  ovh_edge_rules = concat(
    [
      {
        sequence = 0
        action   = "permit"
        protocol = "tcp"
        tcpOption = {
          option = "established"
        }
      },
      {
        sequence = 1
        action   = "permit"
        protocol = "icmp"
      }
    ],
    concat(
      [
        for index, entry in local.ingress : merge(
          {
            sequence        = index + 2
            action          = "permit"
            protocol        = entry.protocol
            destinationPort = entry.from
          },
          entry.protocol == "tcp" ? {
            tcpOption = {
              option = "syn"
            }
          } : {}
        )
        if entry.from == entry.to
      ],
      [
        for index, entry in local.ingress : merge(
          {
            sequence = index + 2
            action   = "permit"
            protocol = entry.protocol
            destinationPortRange = {
              from = entry.from
              to   = entry.to
            }
          },
          entry.protocol == "tcp" ? {
            tcpOption = {
              option = "syn"
            }
          } : {}
        )
        if entry.from != entry.to
      ]
    ),
    [
      {
        sequence        = local.ingress_rule_end
        action          = "permit"
        protocol        = "udp"
        destinationPort = var.wireguard_port
      },
      {
        sequence   = local.ingress_rule_end + 1
        action     = "permit"
        protocol   = "udp"
        sourcePort = 53
      },
      {
        sequence   = local.ingress_rule_end + 2
        action     = "permit"
        protocol   = "udp"
        sourcePort = 123
      }
    ],
    var.bootstrap_complete ? [] : [
      {
        sequence        = local.ingress_rule_end + 3
        action          = "permit"
        protocol        = "tcp"
        source          = var.bootstrap_ssh_cidr
        destinationPort = 22
        tcpOption = {
          option = "syn"
        }
      }
    ],
    [
      {
        sequence = 19
        action   = "deny"
        protocol = "ipv4"
      }
    ]
  )

  edge_destination_ports = compact([
    for rule in local.ovh_edge_rules : try(
      "${rule.protocol}:${rule.destinationPort}",
      "${rule.protocol}:${rule.destinationPortRange.from}-${rule.destinationPortRange.to}",
      ""
    )
  ])
  expected_destination_ports = concat(
    [for entry in local.ingress : "${entry.protocol}:${entry.from == entry.to ? tostring(entry.from) : "${entry.from}-${entry.to}"}"],
    ["udp:${var.wireguard_port}"],
    var.bootstrap_complete ? [] : ["tcp:22"]
  )
  edge_ssh_rules = [
    for rule in local.ovh_edge_rules : rule
    if try(rule.protocol, "") == "tcp" && try(rule.destinationPort, 0) == 22
  ]
}

check "edge_firewall" {
  assert {
    condition     = length(local.ovh_edge_rules) <= 20 && length(distinct([for rule in local.ovh_edge_rules : rule.sequence])) == length(local.ovh_edge_rules)
    error_message = "OVH Edge Network Firewall rules exceed the limit or reuse a sequence number."
  }

  assert {
    condition     = toset(local.edge_destination_ports) == toset(local.expected_destination_ports)
    error_message = "OVH Edge Network Firewall destination ports do not match the ingress contract."
  }

  assert {
    condition     = length(local.edge_ssh_rules) == (var.bootstrap_complete ? 0 : 1)
    error_message = "Public SSH must exist only while estuary bootstrap is incomplete."
  }
}

resource "ovh_ip_firewall" "estuary" {
  ip             = local.estuary_cidr
  ip_on_firewall = local.estuary_ipv4
  enabled        = true
}

resource "terraform_data" "estuary_edge_rules" {
  triggers_replace = [
    local.estuary_ipv4,
    sha256(jsonencode(local.ovh_edge_rules)),
  ]

  provisioner "local-exec" {
    command = "python3 ${path.module}/scripts/sync_ovh_firewall.py"

    environment = {
      OVH_FIREWALL_CIDR  = local.estuary_cidr
      OVH_FIREWALL_IP    = local.estuary_ipv4
      OVH_FIREWALL_RULES = jsonencode(local.ovh_edge_rules)
    }
  }

  depends_on = [ovh_ip_firewall.estuary]
}

data "cloudflare_zone" "primary" {
  filter = {
    name = var.cloudflare_zone
  }
}

resource "cloudflare_dns_record" "play" {
  zone_id = data.cloudflare_zone.primary.id
  name    = "play.${var.cloudflare_zone}"
  content = local.estuary_ipv4
  type    = "A"
  ttl     = 1
  proxied = false

  comment = "Raw game and Pelican ingress through estuary"
}

resource "cloudflare_dns_record" "minecraft_wildcard" {
  zone_id = data.cloudflare_zone.primary.id
  name    = "*.mc.${var.cloudflare_zone}"
  content = local.estuary_ipv4
  type    = "A"
  ttl     = 1
  proxied = false

  comment = "Raw Minecraft hostname routing through estuary and Infrarust"
}
