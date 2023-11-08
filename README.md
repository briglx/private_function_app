# Private Function App

This project demonstrates how to create a Function App restricting access to only private network. Using the following Azure services:

- Azure Function App
- Azure Networking
- Azure Private Endpoint

# Setup

This setup will deploy the core infrastructure needed to run the the solution:

- Prerequisites
- Core Infrastructure

## Prerequisites

- Azure CLI
- Azure Subscription

**Install Azure CLI**

```bash
# Check if installed
az --version

# Install azure cli
curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash

az --version
```

## Core infrastructure

Configure the environment variables. Copy `example.env` to `.env` and update the values

```bash
# load .env vars (optional)
[ -f .env ] && while IFS= read -r line; do [[ $line =~ ^[^#]*= ]] && eval "export $line"; done < .env

az login --tenant $TENANT_ID
# az login --use-device-code --tenant $TENANT_ID

# Update Core Infrastructure (Optional)
./script/core_infrastructure.sh

# Create Function App Connectivity resources
app_name=prvfuncapp
rg_region=westus3
./script/dev_infrastructure.sh --app_name $app_name --rg_region "$rg_region"
```

Clean up resources
    
```bash
# Delete Function App resources
app_name=prvfuncapp
rg_region=westus3
vnet_hub="vnet-core-westus2"
./script/remove_resources.sh --app_name "$app_name" --rg_region "$rg_region" --vnet_hub "$vnet_hub"
``` 

# Development

You'll need to set up a development environment if you want to develop a new feature or fix issues.

## Setup your dev environment

```bash
# Configure linting and formatting tools
sudo apt-get update
sudo apt-get install -y shellcheck jq

# login to azure cli
az login --tenant $TENANT_ID
```

## Testing

Ideally, all code is checked to verify the following:

- All code passes the checks from the linting tools

To run the linters, run the following commands:

```bash
# Check for scripting errors
shellcheck ./script/*.sh
```

# Common Issues

**This region has quota of 0 instances for your subscription**

You may receive this error when deploying resources. Choose a difference region.

**Can't create function app with private storage**

I wasn't able to create a function app from the cli with private storage. I had to create the function app first, then add the private storage.

# References
* Create a Private endpoint - CLI - https://learn.microsoft.com/en-us/azure/private-link/create-private-endpoint-cli?tabs=dynamic-ip
* Create Function App with private Endpoint https://learn.microsoft.com/en-us/azure/azure-functions/functions-create-vnet
* Create Function APp with Private Storage https://learn.microsoft.com/en-us/samples/azure/azure-quickstart-templates/function-app-storage-private-endpoints/
* Function App Networking Options https://learn.microsoft.com/en-us/azure/azure-functions/functions-networking-options?tabs=azure-cli#restrict-your-storage-account-to-a-virtual-network
