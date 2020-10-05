# toggles on/off auditing and advanced threat protection policy for sql server
locals {
    if_threat_detection_policy_enabled  = var.enable_threat_detection_policy ? [{}] : []
    if_extended_auditing_policy_enabled = var.enable_auditing_policy ? [{}] : []                  
}

# creates random password for postgresSQL admin account
resource "random_password" "replica_pw" {
  length      = 24
  special     = true
}
 
# SQL servers - Secondary server is depends_on Failover Group
resource "azurerm_mssql_server" "replica" {
  count                         = var.enable_failover_group ? 1 : 0
  name                          = "${var.names.product_name}-${var.names.environment}-${var.srvr_id_replica}"
  resource_group_name           = var.resource_group_name
  location                      = var.replica_server_location
  version                       = var.srvr_version
  administrator_login           = var.administrator_login
  administrator_login_password  = random_password.replica_pw.result

  dynamic "extended_auditing_policy" {
        for_each = local.if_extended_auditing_policy_enabled
        content {
            storage_endpoint           = var.storage_endpoint
            storage_account_access_key = var.storage_account_access_key 
            retention_in_days          = var.log_retention_days
        }
    }
}

# Adding AD Admin to SQL Server - Default is "false"
data "azurerm_client_config" "current" {}

resource "azurerm_sql_active_directory_administrator" "aduser2" {
    count                = var.enable_sql_ad_admin ? 1 : 0
    server_name          = azurerm_mssql_server.primary.name
    resource_group_name  = var.resource_group_name
    login                = var.ad_admin_login_name
    tenant_id            = data.azurerm_client_config.current.tenant_id
    object_id            = data.azurerm_client_config.current.object_id
}


# Private Link Endpoint for SQL Server - Existing vnet
data "azurerm_virtual_network" "vnet02" {
    name                = var.virtual_network_name_replica
    resource_group_name = var.vnet_replica_resource_group_name
}

# Subnet service endpoint for postgresSQL Server - Default is "false" 
resource "azurerm_subnet" "snet_ep_replica" {
    count                   = var.enable_private_endpoint ? 1 : 0
    name                    = var.subnet_name_replica
    resource_group_name     = var.vnet_replica_resource_group_name
    virtual_network_name    = var.virtual_network_name_replica
    address_prefixes        = var.allowed_cidrs_replica
    enforce_private_link_endpoint_network_policies = true
}

# Azure SQL Failover Group - Default is "false" 
resource "azurerm_sql_failover_group" "fog" {
  count               = var.enable_failover_group ? 1 : 0
  name                = "fog-${var.names.product_name}-${var.names.environment}-${var.srvr_id}"
  resource_group_name = var.resource_group_name
  server_name         = azurerm_mssql_server.primary.name
  databases           = [azurerm_mssql_database.db.0.id]
  tags                = var.tags
  partner_servers {
      id = azurerm_mssql_server.replica.0.id
    }

  read_write_endpoint_failover_policy {
      mode           = "Automatic"
      grace_minutes  = 60
    }

  readonly_endpoint_failover_policy {
      mode           = "Enabled"
    }
}

# SQL elastic pool - Default is "false"
resource "azurerm_mssql_elasticpool" "ep" {
  count               = var.enable_elasticpool ? 1 : 0
  name                = "ep-${var.names.product_name}-${var.names.environment}-${var.srvr_id}"
  resource_group_name = var.resource_group_name
  location            = var.location
  server_name         = azurerm_mssql_server.primary.name
  license_type        = "LicenseIncluded"
  max_size_gb         = 100

  dynamic "sku" {
        for_each = var.sku
        content {
            name     = sku.value["name"]
            tier     = sku.value["tier"]
            family   = sku.value["family"]
            capacity = sku.value["capacity"]
        }
  }

  dynamic "per_database_settings" {
        for_each = var.per_database_settings
        content {
            min_capacity = per_database_settings.value["min_capacity"]
            max_capacity = per_database_settings.value["max_capacity"]
        }
  }
}

resource "azurerm_sql_firewall_rule" "fw02" {
    count               = var.enable_failover_group && var.enable_firewall_rules && length(var.firewall_rules) > 0 ? length(var.firewall_rules) : 0
    name                = element(var.firewall_rules, count.index).name
    resource_group_name = var.resource_group_name
    server_name         = azurerm_mssql_server.replica.0.name
    start_ip_address    = element(var.firewall_rules, count.index).start_ip_address
    end_ip_address      = element(var.firewall_rules, count.index).end_ip_address
}

# Azure Private Endpoint is a network interface that connects you privately and securely to a service powered by Azure Private Link. 
# Private Endpoint uses a private IP address from your VNet, effectively bringing the service into your VNet. The service could be an Azure service such as Azure Storage, MySQL, etc. or your own Private Link Service.
resource "azurerm_private_endpoint" "pep2" {
    count               = var.enable_failover_group && var.enable_private_endpoint ? 1 : 0
    name                = "ep-${var.names.product_name}-${var.names.environment}-${var.srvr_id_replica}"
    location            = var.replica_server_location
    resource_group_name = var.resource_group_name
    subnet_id           = azurerm_subnet.snet_ep_replica.0.id
    tags                = merge({"Name" = format("%s", "sqldb-private-endpoint")}, var.tags,)

    private_service_connection {
        name                           = "sqldbprivatelink"
        is_manual_connection           = false
        private_connection_resource_id = azurerm_mssql_server.replica.0.id
        subresource_names              = ["sqlServer"]
    }
}

# DNS zone & records for SQL Private endpoints - Default is "false" 
data "azurerm_private_endpoint_connection" "private_ip1" {
    count               = var.enable_private_endpoint ? 1 : 0    
    name                = azurerm_private_endpoint.pep1.0.name
    resource_group_name = var.resource_group_name
    depends_on          = [azurerm_mssql_server.primary]
}

data "azurerm_private_endpoint_connection" "private_ip2" {
    count               = var.enable_failover_group && var.enable_private_endpoint ? 1 : 0
    name                = azurerm_private_endpoint.pep2.0.name
    resource_group_name = var.resource_group_name
    depends_on          = [azurerm_mssql_server.replica]
}

resource "azurerm_private_dns_zone" "dnszone1" {
    count               = var.enable_private_endpoint ? 1 : 0
    name                = "privatelink.database.windows.net"
    resource_group_name = var.resource_group_name
    tags                = merge({"Name" = format("%s", "SQL-Private-DNS-Zone")}, var.tags,)
}

resource "azurerm_private_dns_zone_virtual_network_link" "vnet_link1" {
    count                 = var.enable_private_endpoint ? 1 : 0
    name                  = "vnet-private-zone-link"
    resource_group_name   = var.resource_group_name
    private_dns_zone_name = azurerm_private_dns_zone.dnszone1.0.name
    virtual_network_id    = data.azurerm_virtual_network.vnet01.id
    tags                  = merge({"Name" = format("%s", "vnet-private-zone-link")}, var.tags,)
}

resource "azurerm_private_dns_a_record" "arecord2" {
    count               = var.enable_failover_group && var.enable_private_endpoint ? 1 : 0
    name                = azurerm_mssql_server.replica.0.name
    zone_name           = azurerm_private_dns_zone.dnszone1.0.name
    resource_group_name = var.resource_group_name
    ttl                 = 300
    records             = [data.azurerm_private_endpoint_connection.private_ip2.0.private_service_connection.0.private_ip_address]
}
