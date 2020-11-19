# Logic App demo using local environment, containers and Azure Functions Premium
This simple demo shows following workflow:
1. Triggered by new message in Service Bus
2. Calls httpbin API and get results
3. Parse JSON results
4. Send email with results
5. TBD - write to SQL

## Prepare infrastructure
We will deploy Azure environment for various examples consisting of:
- Office365 connector to send emails
- Virtual Network
- Azure Functions Premium integrated to VNET
- SQL Server running as container in Azure Container Instances integrated to VNET
- Storage Account to be used with Logic App runtime
- Service Bus to be used as trigger for Logic App

```bash
az group create -n lapp2 -l westeurope
az deployment group create -g lapp2 --template-file infra.json
```

