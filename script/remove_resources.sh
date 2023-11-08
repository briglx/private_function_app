#!/bin/bash
#######################################################
# Core Infrastructure Script
# Globals
#   TENANT_ID
# Params
# --app_name        Application Name
# --rg_region       Resource Region. Default westus3
# --vnet_hub        Hub vnet name.
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
app_name=${app_name:-prvfuncapp}
rg_region=${rg_region:-westus3}
dev_name="vnet-dev"
vnet_dev="${dev_name}-${rg_region}"

# Validate params
if [ -z "$app_name" ]; then
  echo "app_name is required"
  exit 1
fi

if [ -z "$rg_region" ]; then
  echo "rg_region is required"
  exit 1
fi

if [ -z "$vnet_hub" ]; then
  echo "vnet_hub is required"
  exit 1
fi

rg_region_connectivity="rg_connectivity_$rg_region"
rg_name="${app_name}_${rg_region}_rg"

remove_dev_networking(){
    local rg_spoke="$1"
    local vnet_spoke="$2"
    local vnet_hub="$3"

    vnet_hub_info=$(az network vnet list --query "[?name=='$vnet_hub'] | [0]")
    # vnet_hub_id=$(echo "$vnet_hub_info" | jq -r '.id')
    rg_hub=$(echo "$vnet_hub_info" | jq -r '.resourceGroup')
    # vnet_spoke_id=$(az network vnet list --query "[?name=='$vnet_spoke'].id" -o tsv)

    # Should be taken care of by removing the resource group
    # echo "Deleting spoke vnet $vnet_spoke in $rg_spoke"
    
    # # Create Dev Vnet
    # if [ -n "$vnet_spoke_id" ]; then
    #     echo "vnet $vnet_spoke already exists."
    # else
    #     az network vnet create --resource-group "$rg_spoke" --name "$vnet_spoke" --address-prefixes "$vnet_dev_prefix"
    #     az network vnet subnet create --resource-group "$rg_spoke" --vnet-name "$vnet_spoke" --name "$subnet_function_app_name" --address-prefixes "$subnet_function_app_prefix" --delegations "Microsoft.Web/serverFarms"
    #     az network vnet subnet create --resource-group "$rg_spoke" --vnet-name "$vnet_spoke" --name "$subnet_prv_endpoint_name" --address-prefixes "$subnet_prv_endpoint_prefix" --disable-private-endpoint-network-policies
    #     az network vnet subnet create --resource-group "$rg_spoke" --vnet-name "$vnet_spoke" --name "$subnet_integration_name" --address-prefixes "$subnet_integration_prefix"
    # fi

    # Delete Spoke to Hub Peering
    echo "Deleting Peering $vnet_hub to $vnet_spoke"
    if az network vnet peering show --resource-group "$rg_hub" --name "${vnet_hub}-${vnet_spoke}" --vnet "${vnet_hub}" &>/dev/null; then
        az network vnet peering delete --resource-group "$rg_hub" --name "${vnet_hub}-${vnet_spoke}" --vnet-name "$vnet_hub"
    else
        echo "vnet peering ${vnet_hub}-${vnet_spoke} doesn't exist."
    fi
    echo "Deleting Peering $vnet_spoke to $vnet_hub"
    if az network vnet peering show --resource-group "$rg_spoke" --name "${vnet_spoke}-${vnet_hub}"  --vnet-name "$vnet_spoke" &>/dev/null; then
        az network vnet peering delete --resource-group "$rg_spoke" --name "${vnet_spoke}-${vnet_hub}"  --vnet-name "$vnet_spoke"
    else
        echo "vnet peering ${vnet_spoke}-${vnet_hub} doesn't exist."
    fi

    # Delete Link to Storage DNS Zone for vnet
    private_dns_zone_link_name="vnet-dev-private-link-resolution"
    private_dns_zones=(
        "privatelink.blob.core.windows.net"
        "privatelink.file.core.windows.net"
        "privatelink.queue.core.windows.net"
        "privatelink.table.core.windows.net"
    )
    for private_dns_zone_name in "${private_dns_zones[@]}"; do
        echo "Deleting $private_dns_zone_name Private DNS zone link $private_dns_zone_link_name to vnet $vnet_spoke"
        
        if az network private-dns link vnet show --resource-group "$rg_hub" --zone-name "$private_dns_zone_name" --name "$private_dns_zone_link_name" &>/dev/null; then
            az network private-dns link vnet delete --resource-group "$rg_hub" --zone-name "$private_dns_zone_name" --name "$private_dns_zone_link_name"
        else
            echo "$private_dns_zone_name Private DNS zone link $private_dns_zone_link_name to vnet $vnet_spoke doesn't exist."
        fi
    done

}

remove_bad_dns_zones(){
    local rg_name=$1

    zones=$(az network private-dns zone list --resource-group "$rg_name" --query "[].name" -o tsv)

    for zone in $zones; do
        echo "Deleting Private DNS zone $zone"
        az network private-dns zone delete --resource-group "$rg_name" --name "$zone" --yes
    done

}
# remove_dev_infra(){

# }

# Remove Dev Resources
# remove_resource_group "$rg_name"
# remove_resource_group "$rg_region_connectivity"
# remove_dev_networking "$rg_region_connectivity" "$vnet_dev" "$vnet_hub"
remove_bad_dns_zones prvfuncapp_westus3_rg