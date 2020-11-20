FROM mcr.microsoft.com/azure-functions/dotnet:3.0-appservice

ENV AzureWebJobsScriptRoot=/home/site/wwwroot
ENV AzureFunctionsJobHost__Logging__Console__IsEnabled=true
ENV FUNCTIONS_V2_COMPATIBILITY_MODE=true

COPY ./bin/Release/netcoreapp3.1/publish/ /home/site/wwwroot