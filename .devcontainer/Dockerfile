FROM mcr.microsoft.com/devcontainers/python:3.10-bullseye

RUN apt-get -y update && apt-get install -y ca-certificates curl apt-transport-https lsb-release gnupg vim unzip

# Install Azure CLI latest (2.51.0)
RUN curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash

# Install Azure Function Core Tools 4.0
COPY ./script/install_az_func_core_tools.sh .
RUN ./install_az_func_core_tools.sh

# Install bicep
RUN az bicep install

# Helpful aliases
RUN echo 'alias ll='"'"'ls $LS_OPTIONS -al'"'"'' >> /etc/bash.bashrc 

# Copy requirements.txt
COPY ./functions/requirements.txt .

# Install requirements.txt
RUN pip3 install -r requirements.txt