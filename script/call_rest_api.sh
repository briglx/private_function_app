#!/bin/bash
#######################################################
# Call Azure Rest API
# Globals
#   TENANT_ID
#   SUBSCRIPTION_ID
#   CICD_CLIENT_ID
#   CICD_CLIENT_SECRET
# Params
# --rg_name     Resource Group Name
# --rg_region   Resource Region. Default westus3
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
# Azure AD app details
client_id="$CICD_CLIENT_ID"
client_secret="$CICD_CLIENT_SECRET"
rg_region="westus2"
server_name="test"

# Azure API endpoints
authorization_endpoint="https://login.microsoftonline.com/common/oauth2/v2.0/token"
resource_url="https://management.azure.com/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${rg_region}/providers/Microsoft.Web/serverfarms/${server_name}/usages?api-version=2022-03-01"

# Requesting Access Token
access_token=$(curl -s -X POST \
  "$authorization_endpoint" \
  -d "client_id=$client_id" \
  -d "client_secret=$client_secret" \
  -d "grant_type=client_credentials" \
  -d "scope=https://management.azure.com/.default" \
  -d "tenant=$TENANT_ID" | jq -r '.access_token')

if [ -z "$access_token" ]; then
  echo "Failed to get access token"
  exit 1
fi

# Making API request
response=$(curl -s -X GET \
  "$resource_url" \
  -H "Authorization: Bearer $access_token")

# Handle API response
echo "Azure API response:"
echo "$response"
