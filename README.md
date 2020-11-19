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
- SQL Server running as container in Azure Container Instances integrated to VNET (for Functions and ACI demos) and one on public endpoint (for local debug demo)
- HTTPbin API in Azure Container Instances integrated to VNET (for Functions and ACI demos) and one on public endpoint (for local debug demo)
- Storage Account to be used with Logic App runtime
- Service Bus to be used as trigger for Logic App
- MSSQL Tools in Azure Container Instances integrated to VNET to show database content

```powershell
az group create -n lapp -l westeurope
az deployment group create -g lapp -n infra --template-file infra.json
```

After resources are deployed got to portal, search for office365 connection and click on Authorize.

## Run Logic App in local PC environment
Open workflow in designer by right clicking on workflow.json and selecting Open in Designer. Go to Email connector and create new connection and Save.

Go to local.settings.json in root folder and update variables with connection strings to storage, service bus and database. To gather all details we can use CLI:

```powershell
# Storage connection string
$storageName = (az deployment group show -n infra -g lapp --query properties.outputs.storageName.value -o tsv)
az storage account show-connection-string -g lapp -n $storageName --query connectionString -o tsv

# Service bus connection string
$serviceBusName = (az deployment group show -n infra -g lapp --query properties.outputs.serviceBusName.value -o tsv)
az servicebus namespace authorization-rule keys list --namespace-name $serviceBusName -g lapp -n lappListener --query primaryConnectionString -o tsv

# SQL Server public ip
az container show -n sql-server-public -g lapp --query ipAddress.ip -o tsv
```

For local debugging also modify workflow-designtime/local.settings.json AzureWebJobsStorage to point to Azure Storage.

Hit F5 to run Logic App locally.

Right click on workflow.json and select Overview to see individual runs and steps.

In Azure portal go to Service Bus, lapp queue and create message of type text.

Check you have received email with message.

Check data written to database - in this demo we are using sql-server-public.

```powershell
az container exec -n sqltools-private -g lapp --exec-command /bin/bash
sqlcmd -S 20.71.76.176 -d master -U sa -P "Azure12345678!" -Q "SELECT * FROM myTable"
exit
```

## Run Logic App in Azure Functions Premium with private networking
TBD

## Run Logic App in Azure Container Instance with private networking
TBD

## Run Logic App in Kubernetes with private networking
TBD

