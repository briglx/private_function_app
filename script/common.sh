#!/bin/bash

# Definition of common subroutines
create_resource_group(){
    local rg_name="$1"
    local rg_region="$2"

    echo "creating resource group $rg_name in $rg_region"

    if az group show --name "$rg_name" &>/dev/null; then
        echo "Resource group $rg_name already exists."
    else  
        if result=$(az group create --name "$rg_name" --location "$rg_region"); then
            echo "Creation successful"
        else
            echo "Creation failed"
            echo "$result"
        fi
    fi
}

remove_resource_group(){
    local rg_name="$1"

    # Remove Resource Group
    if az group show --name "$rg_name" &>/dev/null; then
        echo "Resource group $rg_name exists. Deleting..."
        
        if result=$(az group delete --name "$rg_name" --yes); then
            echo "Deletion successful"
        else
            echo "Deletion failed"
            echo "$result"
        fi
    fi
}

create_vnet(){
    local vnet_name="$1"
    local rg_name="$2"
    local vnet_cidr="$3"

    echo "creating vnet $vnet_name in $rg_name with cidr $vnet_cidr"

    if az network vnet show --resource-group "$rg_name" --name "$vnet_name" &>/dev/null; then
        echo "vnet $vnet_name already exists."
    else  
        if result=$(az network vnet create --resource-group "$rg_name" --name "$vnet_name" --address-prefixes "$vnet_cidr"); then
            echo "Creation successful"
        else
            echo "Creation failed"
            echo "$result"
        fi
    fi

}

unique_string(){

    local rg_name="$1"

    unique_string=$(echo -n "$(az group show --name "$rg_name" --query id)" | md5sum | cut -c 1-13)

    echo "$unique_string" 
}