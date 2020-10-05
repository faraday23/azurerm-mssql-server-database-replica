output "resource_group_name" {
  description = "The name of the resource group in which resources are created"  
  value       = var.resource_group_name
}

output "administrator_login" {
  value       = var.administrator_login
  sensitive   = true
  description = "The mssql instance login for the admin."
}

output "replica_server_pw" {
  value       = random_password.replica_pw.result
  sensitive   = true
  description = "The postgresql replica server password for the admin."
}

output "replica_mssql_server_id" {
  description = "The replica Microsoft SQL Server ID"
  value       = element(concat(azurerm_mssql_server.replica.*.id, [""]), 0)
}

output "replica_mssql_server_fqdn" {
  description = "The fully qualified domain name of the replica Azure SQL Server" 
  value       = element(concat(azurerm_mssql_server.replica.*.fully_qualified_domain_name, [""]), 0)
}

output "sql_failover_group_id" {
  description = "A failover group of databases on a collection of Azure SQL servers."
  value       = element(concat(azurerm_sql_failover_group.fog.*.id, [""]), 0)
}

# private link endpoint outputs
output "replica_sql_server_private_endpoint" {
  description = "id of the Primary SQL server Private Endpoint"
  value       = element(concat(azurerm_private_endpoint.pep2.*.id, [""]), 0)
}

output "sql_server_private_dns_zone_domain" {
  description = "DNS zone name of SQL server Private endpoints dns name records"
  value       = element(concat(azurerm_private_dns_zone.dnszone1.*.name, [""]), 0)
}

output "replica_sql_server_private_endpoint_ip" {
  description = "replica SQL server private endpoint IPv4 Addresses "
  value = element(concat(data.azurerm_private_endpoint_connection.private_ip2.*.private_service_connection.0.private_ip_address, [""]), 0)
}

output "replica_sql_server_private_endpoint_fqdn" {
  description = "replica SQL server private endpoint IPv4 Addresses "
  value = element(concat(azurerm_private_dns_a_record.arecord2.*.fqdn, [""]), 0)
}
