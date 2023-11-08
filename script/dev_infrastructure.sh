#!/bin/bash
#######################################################
# Core Infrastructure Script
# Globals
#   TENANT_ID
# Params
# --rg_region Resource Region. Default westus3
#######################################################
echo starting script

# Stop on errors
set -e

## Globals
PROJ_ROOT_PATH=$(cd "$(dirname "$0")"/..; pwd)
echo "Project root: $PROJ_ROOT_PATH"
SCRIPT_DIRECTORY="${PROJ_ROOT_PATH}/script"

# shellcheck source=common.sh
source "${SCRIPT_DIRECTORY}/common.sh"

# Global
app_name=${app_name:-prvfuncapp}
rg_region=${rg_region:-westus3}

# Parse params
while [ $# -gt 0 ]; do
  if [[ $1 == *"--"* ]]; then
 param="${1/--/}"
 declare "$param"="$2"
  fi
 shift
done

# Validate params
if [ -z "$app_name" ]; then
  echo app_name is required
  exit 1
fi

if [ -z "$rg_region" ]; then
  echo rg_region is required
  exit 1
fi

#######################################################
# Variables RG
#######################################################
# Global
# app_name="prvfuncapp"
# rg_region="westus2"
# rg_region="westus"
# rg_region="westus3"
rg_workspace="rg_management_westus2"
rg_region_connectivity="rg_connectivity_${rg_region}"

# Variables RG
rg_name="${app_name}_${rg_region}_rg"
randomIdentifier=$(( RANDOM * RANDOM ))
randomIdentifier=$(unique_string "$rg_name")

appinsight_name=$(echo "${app_name}${randomIdentifier}appi" | tr -d '_-')
appservice_plan_name=$(echo "${app_name}${randomIdentifier}asp" | tr -d '_-')
function_storage_account_name=$(echo "func_${randomIdentifier}sa" | tr -d '_-')
function_content_share_name=function-content-share
func_app_name=$(echo "${app_name}${randomIdentifier}fa" | tr -d '_-')

# Core Vnet
vnet_core_name="vnet-core-westus2"
# vnet_core_cidr='10.0.0.0/16'
# vnet_core_subnet_bastion_name=AzureBastionSubnet
# vnet_core_subnet_bastion_cidr='10.0.255.64/27'
# vnet_core_subnet_bastion_ip_bastion_name=core_bastion_ip
# vnet_core_subnet_bastion_bastion_core_name=core_bastion
# vnet_core_subnet_jump_box_name=snet-jumpbox
# vnet_core_subnet_jump_box_cidr='10.0.0.0/29'
# vnet_core_subnet_firewall_name=snet-firewall
# vnet_core_subnet_firewall_cidr='10.0.0.8/29'
# vnet_core_subnet_management_name=snet-management
# vnet_core_subnet_management_cidr='10.0.0.64/26'
# private_dns_zones=(
#     "privatelink.blob.core.windows.net"
#     "privatelink.file.core.windows.net"
#     "privatelink.queue.core.windows.net"
#     "privatelink.table.core.windows.net"
# )

# Dev Vnet
dev_name="vnet-dev"
vnet_dev="${dev_name}-${rg_region}"
vnet_dev_prefix="10.2.0.0/16"
subnet_function_app_name=snet-func
subnet_function_app_prefix="10.2.0.0/26"
subnet_prv_endpoint_name=snet-prv-endpoint
subnet_prv_endpoint_prefix="10.2.0.64/26"
subnet_integration_name=snet-integration
subnet_integration_prefix="10.2.0.128/26"


setup_networking(){
    # Create vnet, subnets, peering, and link to private dns zone
    local rg_spoke="$1"
    local vnet_spoke="$2"
    local vnet_hub="$3"

    echo "creating spoke vnet $vnet_spoke in $rg_spoke"

    vnet_hub_info=$(az network vnet list --query "[?name=='$vnet_hub'] | [0]")
    vnet_hub_id=$(echo "$vnet_hub_info" | jq -r '.id')
    rg_hub=$(echo "$vnet_hub_info" | jq -r '.resourceGroup')
    vnet_spoke_info=$(az network vnet list --query "[?name=='$vnet_spoke'] | [0]")
    vnet_spoke_id=$(echo "$vnet_spoke_info" | jq -r '.id')
    vnet_spoke_region=$(echo "$vnet_spoke_info" | jq -r '.location')

    if [ -z "$vnet_hub_id" ]; then
        echo "VNet $vnet_hub not found in any resource group or there was an issue retrieving the VNet information."
        exit 1
    fi

    # Create Spoke Vnet
    if [ -n "$vnet_spoke_id" ]; then
        echo "vnet $vnet_spoke already exists."
    else
        az network vnet create --resource-group "$rg_spoke" --name "$vnet_spoke" --address-prefixes "$vnet_dev_prefix"
        az network vnet subnet create --resource-group "$rg_spoke" --vnet-name "$vnet_spoke" --name "$subnet_function_app_name" --address-prefixes "$subnet_function_app_prefix" --delegations "Microsoft.Web/serverFarms"
        az network vnet subnet create --resource-group "$rg_spoke" --vnet-name "$vnet_spoke" --name "$subnet_prv_endpoint_name" --address-prefixes "$subnet_prv_endpoint_prefix" --disable-private-endpoint-network-policies
        az network vnet subnet create --resource-group "$rg_spoke" --vnet-name "$vnet_spoke" --name "$subnet_integration_name" --address-prefixes "$subnet_integration_prefix"
    fi

    # Enable Network watcher
    echo creating network watcher in "$vnet_spoke_region"
    if az network watcher list --query "[?location=='$vnet_spoke_region']" &>/dev/null; then
        echo "Network watcher already exists."
    else  
        az network watcher configure --resource-group "$rg_spoke" --locations "$vnet_spoke_region" --enabled
    fi

    # Peer Dev Vnet to Core
    echo "Peering $vnet_spoke to $vnet_hub"
    if az network vnet peering show --resource-group "$rg_spoke" --name "${vnet_spoke}-${vnet_hub}" --vnet "${vnet_spoke}" &>/dev/null; then
        echo "vnet peering ${vnet_hub}-${vnet_spoke} already exists."
    else
        az network vnet peering create --name "${vnet_hub}-${vnet_spoke}" --resource-group "$rg_hub" --vnet-name "$vnet_hub" --remote-vnet "$vnet_spoke_id" --allow-vnet-access --allow-forwarded-traffic
        az network vnet peering create --name "${vnet_spoke}-${vnet_hub}" --resource-group "$rg_spoke" --vnet-name "$vnet_spoke" --remote-vnet "$vnet_hub_id" --allow-vnet-access --allow-forwarded-traffic
    fi

    # Link vnet to Storage DNS Zone for resolution
    echo "Linking $vnet_spoke to private dns zone"
    if az network private-dns link vnet show --resource-group "$rg_hub" --name vnet-dev-private-link-resolution --zone-name "privatelink.blob.core.windows.net" &>/dev/null; then
        echo "Vnet link to private dns for $vnet_spoke already exists."
    else
        az network private-dns link vnet create --resource-group "$rg_hub" --zone-name "privatelink.blob.core.windows.net" --name vnet-dev-private-link-resolution --virtual-network "$vnet_spoke_id" --registration-enabled false
        az network private-dns link vnet create --resource-group "$rg_hub" --zone-name "privatelink.file.core.windows.net" --name vnet-dev-private-link-resolution --virtual-network "$vnet_spoke_id" --registration-enabled false
        az network private-dns link vnet create --resource-group "$rg_hub" --zone-name "privatelink.queue.core.windows.net" --name vnet-dev-private-link-resolution --virtual-network "$vnet_spoke_id" --registration-enabled false
        az network private-dns link vnet create --resource-group "$rg_hub" --zone-name "privatelink.table.core.windows.net" --name vnet-dev-private-link-resolution --virtual-network "$vnet_spoke_id" --registration-enabled false
    fi
}

create_dev_infra(){
    local rg_name="$1"
    local rg_workspace="$2"
    
    # Create Application Insights
    if az monitor app-insights component show --app "$appinsight_name" --resource-group "$rg_name" &>/dev/null; then
        echo "Application Insights resource $appinsight_name already exists in the resource group $rg_name."
    else
        echo "Application Insights resource $appinsight_name does not exist. Creating..."
        
        workspace_id=$(az monitor log-analytics workspace list --resource-group "$rg_workspace" --query "[].id" -o tsv)
        az monitor app-insights component create --app "$appinsight_name" --location "$rg_region" --kind web --resource-group "$rg_name" --workspace "$workspace_id"
        # az monitor app-insights component create --app "$appinsight_name" --location "$rg_region" --kind web --resource-group "$rg_name" --application-type web
    fi

    # Create App Service Plan (Function App, Logic App, Web App)
    if az functionapp plan show --name "$appservice_plan_name" --resource-group "$rg_name" &>/dev/null; then
        echo "App Service Plan resource $appservice_plan_name already exists in the resource group $rg_name."
    else
        echo "App Service Plan resource $appservice_plan_name does not exist. Creating..."
        az functionapp plan create --name "$appservice_plan_name" --resource-group "$rg_name" --location "$rg_region" --is-linux --min-instances 1 --max-burst 10 --sku EP1
    fi

    # Create storage account account. Needs to be V2
    if az storage account show --name "$function_storage_account_name" --resource-group "$rg_name" &>/dev/null; then
        echo "Storage Account resource $function_storage_account_name already exists in the resource group $rg_name."
    else
        echo "Storage Account resource $function_storage_account_name does not exist. Creating..."
        az storage account create --name "$function_storage_account_name" --resource-group "$rg_name" --location "$rg_region" --sku  Standard_LRS --kind StorageV2
    fi
    # az storage account create --name "$function_storage_account_name" --resource-group "$rg_name" --location "$rg_region" --sku  Standard_LRS 
    
    # Create file share
    # storage_key=$(az storage account keys list --account-name "$function_storage_account_name" --resource-group "$rg_name" --query "[0].value" --output tsv)
    # if az storage share show --name "${function_content_share_name}" --account-name "$function_storage_account_name" --account-key "$storage_key" &>/dev/null; then
    #     echo "Storage Share resource $function_content_share_name already exists in the storage account $function_storage_account_name."
    # else
    #     echo "Storage Share resource $function_content_share_name does not exist. Creating..."
    #     if az storage share create --name "${function_content_share_name}" --account-name "$function_storage_account_name" --account-key "$storage_key" &>/dev/null; then
    #         echo success
    #     else
    #         echo failed. Storage may be set as private
    #     fi
    # fi

    

}

disable_public_access(){
    local rg_name="$1"
    local storage_account_name="$2"

    # Disable public access
    storage_account_info=$(az storage account show --name "$storage_account_name" --resource-group "$rg_name" --query 'publicNetworkAccess' -o tsv 2>/dev/null)
    if [[ "$storage_account_info" == "Disabled" ]]; then
        echo "Storage Account resource $storage_account_name public access already disabled."
    else
        az storage account update --name "$storage_account_name" --resource-group "$rg_name" --default-action Deny --bypass None --allow-blob-public-access false --public-network-access disabled
    fi
}

create_storage_private_endpoint(){
    local storage_account_name=$1
    local vnet_hub="$2"
    local vnet_spoke="$3"
    # local vnet_connectivity="$2"
    
    storage_id=$(az storage account list --resource-group "$rg_name" --query "[?name=='$storage_account_name'].id" --output tsv)
    rg_connectivity=$(az network vnet list --query "[?name=='$vnet_spoke'].resourceGroup" --output tsv)

    vnet_hub_info=$(az network vnet list --query "[?name=='$vnet_hub'] | [0]")
    vnet_hub_id=$(echo "$vnet_hub_info" | jq -r '.id')
    rg_hub=$(echo "$vnet_hub_info" | jq -r '.resourceGroup')

    # storage_id=$(az storage account list --resource-group "$rg_name" --query '[].[id]' --output tsv)
    sub_resources=(
        "blob"
        "file"
        "queue"
        "table"
    )
    for sub_resource in "${sub_resources[@]}"; do
        # Create private endpoint for blob storage 
        echo creating private endpoint for "$sub_resource"
        if az network private-endpoint show --name "${storage_account_name}-${sub_resource}-private-endpoint" --resource-group "$rg_connectivity" &>/dev/null; then
            echo "Private endpoint ${storage_account_name}-${sub_resource}-private-endpoint already exists in $rg_connectivity."
        else
            az network private-endpoint create --connection-name "${storage_account_name}${sub_resource}PrivateLinkConnection" --name "${storage_account_name}-${sub_resource}-private-endpoint" --private-connection-resource-id "$storage_id" --resource-group "$rg_connectivity" --vnet-name "$vnet_spoke" --subnet "$subnet_prv_endpoint_name" --group-id "[${sub_resource}]" --nic-name "${storage_account_name}-${sub_resource}-private-endpoint-nic"
        fi

        # Configure private-endpoint integration with private DNS zone
        echo "Configuring private-endpoint integration with private DNS zone for $sub_resource"
        result=$(az network private-endpoint dns-zone-group list --resource-group "$rg_connectivity" --endpoint-name "${storage_account_name}-${sub_resource}-private-endpoint" --query 'length([])')
        if [ ! "$result" -eq 0 ]; then
            echo "Private endpoint DNS zone integration ${storage_account_name}-${sub_resource}-private-endpoint already exists in $rg_connectivity."
        else
            private_dns_zone_id=$(az network private-dns zone list --query "[?name == 'privatelink.${sub_resource}.core.windows.net'].id" --output tsv)
            az network private-endpoint dns-zone-group create --resource-group "$rg_connectivity" --endpoint-name "${storage_account_name}-${sub_resource}-private-endpoint" --name "privatelink.${sub_resource}.core.windows.net" --private-dns-zone "$private_dns_zone_id" --zone-name config
        fi
    done
    # az network private-endpoint create --connection-name "${storage_account_name}BlobPrivateLinkConnection" --name "${storage_account_name}-blob-private-endpoint" --private-connection-resource-id "$storage_id" --resource-group "$rg_connectivity" --vnet-name "$vnet_spoke" --subnet "$subnet_prv_endpoint_name"  --group-id "[blob]"
    # az network private-endpoint create --connection-name "${storage_account_name}FilePrivateLinkConnection" --name "${storage_account_name}-file-private-endpoint" --private-connection-resource-id "$storage_id" --resource-group "$rg_connectivity" --vnet-name "$vnet_spoke" --subnet "$subnet_prv_endpoint_name" --group-id "[file]"
    # az network private-endpoint create --connection-name "${storage_account_name}TablePrivateLinkConnection" --name "${storage_account_name}-table-private-endpoint" --private-connection-resource-id "$storage_id" --resource-group "$rg_connectivity" --vnet-name "$vnet_spoke" --subnet "$subnet_prv_endpoint_name" --group-id "[table]"
    # az network private-endpoint create --connection-name "${storage_account_name}QueuePrivateLinkConnection" --name "${storage_account_name}-queue-private-endpoint" --private-connection-resource-id "$storage_id" --resource-group "$rg_connectivity" --vnet-name "$vnet_spoke" --subnet "$subnet_prv_endpoint_name" --group-id "[queue]"
    
    # Configure private-endpoint integration with private DNS zone
    # This will update records in the Blob Storage Private DNS Zone when the Private link changes 
    # private_dns_zone_id=$(az network private-dns zone list --resource-group "$rg_core" --query "[?name == 'privatelink.blob.core.windows.net'] | [0].id" --output tsv)
    # az network private-endpoint dns-zone-group create --resource-group "$rg_core" --endpoint-name "${function_storage_account_name}-blob-private-endpoint" --name privatelink.blob.core.windows.net  --private-dns-zone "$private_dns_zone_id" --zone-name config
    # private_dns_zone_id=$(az network private-dns zone list --resource-group "$rg_core" --query "[?name == 'privatelink.file.core.windows.net'] | [0].id" --output tsv)
    # az network private-endpoint dns-zone-group create --resource-group "$rg_core" --endpoint-name "${function_storage_account_name}-file-private-endpoint" --name privatelink.file.core.windows.net  --private-dns-zone "$private_dns_zone_id" --zone-name config
    # private_dns_zone_id=$(az network private-dns zone list --resource-group "$rg_core" --query "[?name == 'privatelink.table.core.windows.net'] | [0].id" --output tsv)
    # az network private-endpoint dns-zone-group create --resource-group "$rg_core" --endpoint-name "${function_storage_account_name}-table-private-endpoint" --name privatelink.table.core.windows.net  --private-dns-zone "$private_dns_zone_id" --zone-name config
    # private_dns_zone_id=$(az network private-dns zone list --resource-group "$rg_core" --query "[?name == 'privatelink.queue.core.windows.net'] | [0].id" --output tsv)
    # az network private-endpoint dns-zone-group create --resource-group "$rg_core" --endpoint-name "${function_storage_account_name}-queue-private-endpoint" --name privatelink.queue.core.windows.net  --private-dns-zone "$private_dns_zone_id" --zone-name config

}

create_function_app(){
    local rg_name=$1
    local storage_account=$2

    # Create Function App
    # Plan: Functions Premium	
    # Enable Public access: Off
    # Enable network inejction: On
    # Use an existing Vnet
    # Enable private endpoints: On
    # Private Endbpoint Name: ...


    app_insight_key=$(az monitor app-insights component show --app "$appinsight_name" --resource-group "$rg_name" --query "instrumentationKey" -o tsv)

    az functionapp create --resource-group "$rg_name" --name "$func_app_name" --runtime Python --runtime-version "3.10" --os-type Linux --plan "$appservice_plan_name" --storage-account "$storage_account" --app-insights "$appinsight_name" --app-insights-key "$app_insight_key"  --functions-version 4

}


# Create Connectivity Resources -----------------------------------
create_resource_group "$rg_region_connectivity" "$rg_region"
# Create spoke network
setup_networking "$rg_region_connectivity" "$vnet_dev" "$vnet_core_name" 

# Create Function App Resources -----------------------------------
create_resource_group "$rg_name" "$rg_region"
create_dev_infra "$rg_name" "$rg_workspace"

create_storage_private_endpoint "$function_storage_account_name" "$vnet_core_name" "$vnet_dev"

create_function_app "$rg_name" "$function_storage_account_name"

disable_public_access "$rg_name" "$function_storage_account_name"