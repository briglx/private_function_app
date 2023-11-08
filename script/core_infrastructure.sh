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

# Global
rg_region=${rg_region:-westus3}

# Parse params
while [ $# -gt 0 ]; do
  if [[ $1 == *"--"* ]]; then
 param="${1/--/}"
 declare "$param"="$2"
  fi
 shift
done

#######################################################
# Variables RG
#######################################################
# Global
app_name="prvfuncapp"
rg_region="westus"
rg_core="rg-core_$rg_region"

# Variables RG
randomIdentifier=$(( RANDOM * RANDOM ))
rg_name="${app_name}_${rg_region}_rg"

appservice_plan_name=$(echo "${app_name}${randomIdentifier}asp" | tr -d '_-')
# func_app_name=$(echo "${app_name}${randomIdentifier}fa" | tr -d '_-')
function_storage_account_name=$(echo "${app_name}${randomIdentifier}sa" | tr -d '_-')
function_content_share_name=function-content-share

appinsight_name=$(echo "${app_name}${randomIdentifier}appi" | tr -d '_-')

# Core Vnet
vnet_core_name="vnet-core-$rg_region"
vnet_core_cidr='10.0.0.0/16'
vnet_core_subnet_bastion_name=AzureBastionSubnet
vnet_core_subnet_bastion_cidr='10.0.255.64/27'
vnet_core_subnet_bastion_ip_bastion_name=core_bastion_ip
vnet_core_subnet_bastion_bastion_core_name=core_bastion
vnet_core_subnet_jump_box_name=snet-jumpbox
vnet_core_subnet_jump_box_cidr='10.0.0.0/29'
vnet_core_subnet_firewall_name=snet-firewall
vnet_core_subnet_firewall_cidr='10.0.0.8/29'
vnet_core_subnet_management_name=snet-management
vnet_core_subnet_management_cidr='10.0.0.64/26'

# Dev Vnet
vnet_dev="vnet-dev-$rg_region"
vnet_dev_prefix='10.2.0.0/16'
subnet_integration_name=snet-integration
subnet_integration_prefix='10.2.0.0/26'
subnet_prv_endpoint_name=snet-prv-endpoint
subnet_prv_endpoint_prefix='10.2.0.64/26'
subnet_function_app_name=snet-func
subnet_function_app_prefix='10.2.0.128/26'


create_core_infra() {
    # Create Resource Group
    echo "creating resource group $rg_core in $rg_region"
    az group create --name "$rg_core" --location "$rg_region"

    # # Network watcher
    # echo creating network watcher in $rg_name
    # az network watcher configure --resource-group $rg_name --locations $rg_region --enabled

    # Create Blob Private DNS Zone
    echo configure dns zone
    az network private-dns zone create --resource-group "$rg_core" --name privatelink.blob.core.windows.net
    az network private-dns zone create --resource-group "$rg_core" --name privatelink.file.core.windows.net
    az network private-dns zone create --resource-group "$rg_core" --name privatelink.queue.core.windows.net
    az network private-dns zone create --resource-group "$rg_core" --name privatelink.table.core.windows.net

    # create core vnet 
    echo creating "$vnet_core_name" vnet in "$rg_core"
    az network vnet create --resource-group "$rg_core" --name "$vnet_core_name" --address-prefixes "$vnet_core_cidr"
    
    # core bastion subnet
    echo creating subnet "$vnet_core_subnet_bastion_name"
    az network vnet subnet create --resource-group "$rg_core" --name $vnet_core_subnet_bastion_name --vnet-name $vnet_core_name --address-prefixes $vnet_core_subnet_bastion_cidr
    az network public-ip create --resource-group"$rg_core" --name $vnet_core_subnet_bastion_ip_bastion_name --sku Standard --location $rg_region --zone 1 2 3
    az network bastion create --resource-group "$rg_core" --name $vnet_core_subnet_bastion_bastion_core_name --public-ip-address $vnet_core_subnet_bastion_ip_bastion_name  --vnet-name $vnet_core_name --location $rg_region
    
    # jumpbox subnet
    echo creating subnet $vnet_core_subnet_jump_box_name
    az network vnet subnet create --resource-group "$rg_core" --name $vnet_core_subnet_jump_box_name --vnet-name $vnet_core_name --address-prefixes $vnet_core_subnet_jump_box_cidr

    # Create firewall subnet
    echo creating subnet $vnet_core_subnet_firewall_name
    az network vnet subnet create --resource-group "$rg_core" --name $vnet_core_subnet_firewall_name --vnet-name $vnet_core_name --address-prefixes $vnet_core_subnet_firewall_cidr

    # Create management subnet
    echo creating subnet $vnet_core_subnet_management_name
    az network vnet subnet create --resource-group "$rg_core" --name $vnet_core_subnet_management_name --vnet-name $vnet_core_name --address-prefixes $vnet_core_subnet_management_cidr

}

create_connectivity_dev(){
    
    # Create Dev Vnet
    az network vnet create -g "$rg_core" -n "$vnet_dev" --address-prefixes "$vnet_dev_prefix"
    az network vnet subnet create -g "$rg_core" --vnet-name "$vnet_dev" -n "$subnet_integration_name" --address-prefixes "$subnet_integration_prefix"
    az network vnet subnet create -g "$rg_core" --vnet-name "$vnet_dev" -n "$subnet_prv_endpoint_name" --address-prefixes "$subnet_prv_endpoint_prefix" --disable-private-endpoint-network-policies
    az network vnet subnet create -g "$rg_core" --vnet-name "$vnet_dev" -n "$subnet_function_app_name" --address-prefixes "$subnet_function_app_prefix" --delegations "Microsoft.Web/serverFarms"

    # Peer Dev Vnet to Core
    az network vnet peering create --name "${vnet_core_name}-${vnet_dev}" --resource-group "$rg_core" --vnet-name "$vnet_core_name" --remote-vnet "$vnet_dev" --allow-vnet-access --allow-forwarded-traffic
    az network vnet peering create --name "${vnet_dev}-${vnet_core_name}" --resource-group "$rg_core" --vnet-name "$vnet_dev" --remote-vnet "$vnet_core_name" --allow-vnet-access --allow-forwarded-traffic

    # Link Dev vnet to Storage DNS Zone for resolution
    az network private-dns link vnet create --resource-group "$rg_core" --zone-name "privatelink.blob.core.windows.net" --name vnet-dev-private-link-resolution --virtual-network "$vnet_dev" --registration-enabled false
    az network private-dns link vnet create --resource-group "$rg_core" --zone-name "privatelink.file.core.windows.net" --name vnet-dev-private-link-resolution --virtual-network "$vnet_dev" --registration-enabled false
    az network private-dns link vnet create --resource-group "$rg_core" --zone-name "privatelink.queue.core.windows.net" --name vnet-dev-private-link-resolution --virtual-network "$vnet_dev" --registration-enabled false
    az network private-dns link vnet create --resource-group "$rg_core" --zone-name "privatelink.table.core.windows.net" --name vnet-dev-private-link-resolution --virtual-network "$vnet_dev" --registration-enabled false

}

create_dev_infra(){

    # Create Resource Group
    echo "creating resource group $rg_name in $rg_region"
    az group create --name "$rg_name" --location "$rg_region"

    # Network watcher
    echo creating network watcher in $rg_name
    az network watcher configure --resource-group $rg_name --locations $rg_region --enabled

    # Create Application Insights
    az monitor app-insights component create --app "$appinsight_name" --location "$rg_region" --kind web --resource-group "$rg_name" --application-type web

    # Create App Service Plan (Function App, Logic App, Web App)
    echo "creating appservice plan $appservice_plan_name"
    response=$(az functionapp plan create --name "$appservice_plan_name" --resource-group "$rg_name" --location "$rg_region" --is-linux --min-instances 1 --max-burst 10 --sku EP1)
    if [[ ${PIPESTATUS[0]} -ne 0 ]]; then
        echo "Failed to appservice" >&2
        exit 1
    fi
    appservice_id=$(jq --raw-output .id <(echo "$response"))
    if [[ -z "$appservice_id" ]]; then
        echo 'missing appservice_id' >&2
        exit 1
    fi

    # Create storage account account. Needs to be V2
    az storage account create --name "$function_storage_account_name" --resource-group "$rg_name" --location "$rg_region" --sku  Standard_LRS 
    
    # Create file share
    storage_key=$(az storage account keys list --account-name "$function_storage_account_name" --query "[0].value" --output tsv)
    az storage share create --name "${function_content_share_name}" --account-name "$function_storage_account_name" --account-key "$storage_key"

    # Disable public access
    az storage account update --name "$function_storage_account_name" --resource-group "$rg_name" --default-action Deny --bypass None --allow-blob-public-access false --public-network-access disabled

}

create_dev_storage_private_endpoint(){

    # Create private endpoint for blob storage 
    storage_id=$(az storage account list --resource-group "$rg_name" --query '[].[id]' --output tsv)
    az network private-endpoint create --connection-name "${function_storage_account_name}BlobPrivateLinkConnection" --name "${function_storage_account_name}-blob-private-endpoint" --private-connection-resource-id "$storage_id" --resource-group "$rg_core" --subnet "$subnet_prv_endpoint_name" --vnet-name "$vnet_dev" --group-id "[blob]"
    az network private-endpoint create --connection-name "${function_storage_account_name}FilePrivateLinkConnection" --name "${function_storage_account_name}-file-private-endpoint" --private-connection-resource-id "$storage_id" --resource-group "$rg_core" --subnet "$subnet_prv_endpoint_name" --vnet-name "$vnet_dev" --group-id "[file]"
    az network private-endpoint create --connection-name "${function_storage_account_name}TablePrivateLinkConnection" --name "${function_storage_account_name}-table-private-endpoint" --private-connection-resource-id "$storage_id" --resource-group "$rg_core" --subnet "$subnet_prv_endpoint_name" --vnet-name "$vnet_dev" --group-id "[table]"
    az network private-endpoint create --connection-name "${function_storage_account_name}QueuePrivateLinkConnection" --name "${function_storage_account_name}-queue-private-endpoint" --private-connection-resource-id "$storage_id" --resource-group "$rg_core" --subnet "$subnet_prv_endpoint_name" --vnet-name "$vnet_dev" --group-id "[queue]"
    

    # Configure private-endpoint integration with private DNS zone
    # This will update records in the Blob Storage Private DNS Zone when the Private link changes 
    private_dns_zone_id=$(az network private-dns zone list --resource-group "$rg_core" --query "[?name == 'privatelink.blob.core.windows.net'] | [0].id" --output tsv)
    az network private-endpoint dns-zone-group create --resource-group "$rg_core" --endpoint-name "${function_storage_account_name}-blob-private-endpoint" --name privatelink.blob.core.windows.net  --private-dns-zone "$private_dns_zone_id" --zone-name config
    private_dns_zone_id=$(az network private-dns zone list --resource-group "$rg_core" --query "[?name == 'privatelink.file.core.windows.net'] | [0].id" --output tsv)
    az network private-endpoint dns-zone-group create --resource-group "$rg_core" --endpoint-name "${function_storage_account_name}-file-private-endpoint" --name privatelink.file.core.windows.net  --private-dns-zone "$private_dns_zone_id" --zone-name config
    private_dns_zone_id=$(az network private-dns zone list --resource-group "$rg_core" --query "[?name == 'privatelink.table.core.windows.net'] | [0].id" --output tsv)
    az network private-endpoint dns-zone-group create --resource-group "$rg_core" --endpoint-name "${function_storage_account_name}-table-private-endpoint" --name privatelink.table.core.windows.net  --private-dns-zone "$private_dns_zone_id" --zone-name config
    private_dns_zone_id=$(az network private-dns zone list --resource-group "$rg_core" --query "[?name == 'privatelink.queue.core.windows.net'] | [0].id" --output tsv)
    az network private-endpoint dns-zone-group create --resource-group "$rg_core" --endpoint-name "${function_storage_account_name}-queue-private-endpoint" --name privatelink.queue.core.windows.net  --private-dns-zone "$private_dns_zone_id" --zone-name config

}

remove_dev_resources(){

    # Remove Resource Group
    if az group show --name "$rg_name" &>/dev/null; then
        echo "Resource group $rg_name exists. Deleting..."
        
        if delete_result=$(az group delete --name "$rg_name" --yes); then
            echo "Deletion successful"
        else
            echo "Deletion failed"
            # Log the $delete_result for further investigation if needed
            echo "$delete_result"
        fi
    fi

    # Connectivity
    # Remove dev vnet
    if az network vnet show --resource-group "$rg_core" --name "$vnet_dev" &>/dev/null; then
        echo "vnet $vnet_dev exists. Deleting..."
        
        if delete_result=$(az network vnet delete --resource-group "$rg_core" --name "$vnet_dev"); then
            echo "Deletion successful"
        else
            echo "Deletion failed"
            # Log the $delete_result for further investigation if needed
            echo "$delete_result"
        fi
    fi
}

# Create Dev Resources

create_connectivity_dev













# # Create Function App Storage Account
# echo "creating function app $func_app_name with storage account $function_storage_account_name"


# Create Function App
# Plan: Functions Premium	
# Enable Public access: Off
# Enable network inejction: On
# Use an existing Vnet
# Enable private endpoints: On
# Private Endbpoint Name: ...
# az functionapp create --resource-group "$rg_name" --name "$func_app_name" --storage-account "$function_storage_account_name"

# # Create Private Endpoint
# func_app_id=$(az functionapp list --resource-group "$rg_name" --query '[].[id]' --output tsv)
# az network private-endpoint create --connection-name connection-1 --name private-endpoint --private-connection-resource-id "$func_app_id" --resource-group "$rg_name" --subnet "$subnet_app_name" --group-id sites --vnet-name "$vnet_dev" 

# # Configure DNS Zone
# az network private-dns zone create --resource-group test-rg --name "privatelink.azurewebsites.net"
# az network private-dns link vnet create --resource-group test-rg --zone-name "privatelink.azurewebsites.net" --name private-link-resolution --virtual-network vnet-1 --registration-enabled false
# az network private-endpoint dns-zone-group create --resource-group test-rg --endpoint-name private-endpoint --name zone-group --private-dns-zone "privatelink.azurewebsites.net" --zone-name webapp




# Create App Service Plan (Function App, Logic App, Web App)
# echo "creating appservice plan $appservice_plan_name"
# response=$(az appservice plan create --name "$appservice_plan_name" --resource-group "$rg_name" --is-linux --location "$rg_region" --sku B1)
# if [[ ${PIPESTATUS[0]} -ne 0 ]]; then
#     echo "Failed to appservice" >&2
#     exit 1
# fi
# appservice_id=$(jq --raw-output .id <(echo "$response"))
# if [[ -z "$appservice_id" ]]; then
#     echo 'missing appservice_id' >&2
#     exit 1
# fi