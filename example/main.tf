# required server inputs
variable "srvr_id" {
  description = "identifier appended to srvr name for more info see https://github.com/[redacted]/python-azure-naming"
  type        = string
}

variable "srvr_id_replica" {
  description = "identifier appended to srvr name for more info see https://github.com/[redacted]/python-azure-naming"
  type        = string
}

# required tags
variable "names" {
  description = "names to be applied to resources"
  type        = map(string)
}

variable "tags" {
  description = "tags to be applied to resources"
  type        = map(string)
}

# Configure Providers
provider "azurerm" {
  version = ">=2.25.0"
  subscription_id = "00000000-0000-0000-0000-00000000"
  features {}
}

##
# Pre-Built Modules 
##

module "subscription" {
  source          = "github.com/Azure-Terraform/terraform-azurerm-subscription-data.git?ref=v1.0.0"
  subscription_id = "00000000-0000-0000-0000-00000000"
}

module "rules" {
  source = "git@github.com:[redacted]/python-azure-naming.git?ref=tf"
}

# For tags and info see https://github.com/Azure-Terraform/terraform-azurerm-metadata 
# For naming convention see https://github.com/[redacted]/python-azure-naming 
module "metadata" {
  source = "github.com/Azure-Terraform/terraform-azurerm-metadata.git?ref=v1.1.0"

  naming_rules = module.rules.yaml
  
  market              = "us"
  location            = "useast1" # for location list see - https://github.com/[redacted]/python-azure-naming#rbaazureregion
  sre_team            = "alpha"
  environment         = "sandbox" # for environment list see - https://github.com/[redacted]/python-azure-naming#rbaenvironment
  project             = "mssql"
  business_unit       = "iog"
  product_group       = "tfe"
  product_name        = "mssql"   # for product name list see - https://github.com/[redacted]/python-azure-naming#rbaproductname
  subscription_id     = "00000000-0000-0000-0000-00000000"
  subscription_type   = "nonprod"
  resource_group_type = "app"
}

# mssql-server storage account
module "storage_acct" {
  source = "../ms_sql_module/storage_account"
  # Required inputs 
  srvr_id             = "01"
  # Pre-Built Modules  
  location            = module.metadata.location
  names               = module.metadata.names
  tags                = module.metadata.tags
  resource_group_name = "rg-azure-demo-mssql-01"
}

# mssql-server module
module "mssql_server" {
  source = "../ms_sql_module/ms_sql_server_service_endpoint"
  # Pre-Built Modules  
  location                       = module.metadata.location
  names                          = module.metadata.names
  tags                           = module.metadata.tags
  # Storage endpoints for audit logs and atp logs
  storage_endpoint               = module.storage_acct.primary_blob_endpoint
  storage_account_access_key     = module.storage_acct.primary_access_key   
  # Required inputs 
  srvr_id                        = "01"
  srvr_id_replica                = "02"
  resource_group_name            = "rg-azure-demo-mssql-01"
  # Enable creation of Database 
  enable_db                      = true
  # SQL server and database audit policies and advanced threat protection 
  enable_auditing_policy         = true
  enable_threat_detection_policy = true
  # SQL failover group
  enable_failover_group          = true
  secondary_sql_server_location  = "westus"
  # SQL server Azure AD administrator 
  enable_sql_ad_admin            = false
  ad_admin_login_name            = "first.last@risk.regn.net"
  ad_admin_login_name_replica    = "first.last@risk.regn.net"
  log_retention_days             = 7
  # SQL server elastic pooling
  enable_elasticpool             = false
  per_database_settings = [{
    max_capacity = 4
    min_capacity = 1
  }]
  sku = [{
    capacity = 4
    family   = "Gen5"
    name     = "GP_Gen5"
    tier     = "GeneralPurpose"
  }]
  # private link endpoint
  enable_private_endpoint        = false 
  public_network_access_enabled  = false      # public access will need to be enabled to use vnet rules
  # vnet rules
  enable_vnet_rule               = false
  # Virtual network - for Existing virtual network
  vnet_resource_group_name         = "rg-azure-demo-mssql-01"       #must be existing resource group within same region as primary server
  vnet_replica_resource_group_name = "rg-azure-demo-mssql-02"       #must be existing resource group within same region as replica server
  virtual_network_name             = "vnet-sandbox-eastus-mssql-01" #must be existing vnet with available address space
  virtual_network_name_replica     = "vnet-sandbox-westus-mssql-02" #must be existing vnet with available address space
  subnet_name_primary              = "default" #must be existing subnet name 
  subnet_name_replica              = "default" #must be existing subnet name 
  # SQL server firewall access control rules
  enable_firewall_rules           = false
  firewall_rules = [
                {name             = "desktop-ip"
                start_ip_address  = "209.243.55.98"
                end_ip_address    = "209.243.55.98"}]
}


