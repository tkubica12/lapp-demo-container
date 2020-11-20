# Logic App demo using local environment, Azure Functions Premium and Kubernetes
This simple demo shows following workflow:
1. Triggered by new message in Service Bus
2. Calls httpbin API and get results
3. Parse JSON results
4. Send email with results
5. Write record to SQL server

We will run this logic app in different environments:
- Local PC
- Azure Function Premium with VNET integration
- Generic Kubernetes cluster as static container
- Generic Kubernetes cluster with serverless scale-to-zero using KEDA

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
- Azure Kubernetes Service

```powershell
az group create -n lapp -l westeurope
az deployment group create -g lapp -n infra --template-file infra.json
```

After resources are deployed got to portal, search for office365 connection and click on Authorize.

## Run Logic App in local PC environment
Open workflow in designer by right clicking on workflow.json and selecting Open in Designer. Go to Email connector and create new connection and Save.

Go to local.settings.json in root folder (use local.settings.json.example and modify) and update variables with connection strings to storage, service bus, database and API endpoint (httpbin). To gather all details we can use CLI:

```powershell
# Storage connection string
$storageName = (az deployment group show -n infra -g lapp --query properties.outputs.storageName.value -o tsv)
az storage account show-connection-string -g lapp -n $storageName --query connectionString -o tsv

# Service bus connection string
$serviceBusName = (az deployment group show -n infra -g lapp --query properties.outputs.serviceBusName.value -o tsv)
az servicebus namespace authorization-rule keys list --namespace-name $serviceBusName -g lapp -n lappListener --query primaryConnectionString -o tsv

# SQL Server public ip
az container show -n sql-server-public -g lapp --query ipAddress.ip -o tsv

# API endpoint public ip
az container show -n httpbin-public -g lapp --query ipAddress.ip -o tsv
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

Make sure you stop Logic App now so we can try running it in different environments.


## Run Logic App in Azure Functions Premium with private networking
There is infrastructure prepared in your environment to run Logic App on Azure Functions Premium integrated to VNET. 
1. Use VSCode Logic Apps (preview) extension to deploy your Logic App. 
2. Go to Application Settings in VSCode and choose (right click) Upload local settings (this will configure secrets such as storage and service bus connection string)
3. Modify sql-connection string to point to private instance of SQL server inside VNET
4. Modify apiEndpoint to refer private instance of httpbin

To get IP address of sql-server-private you can use this command:

```powershell
# SQL Server private ip
az container show -n sql-server-private -g lapp --query ipAddress.ip -o tsv

# API endpoint private ip
az container show -n httpbin-private -g lapp --query ipAddress.ip -o tsv
```

You Logic App should be running now. In Azure portal go to Service Bus, lapp queue and create message of type text.

In portal go to Logic App, Workflows and Monitor.

Check you have received email with message.

Check data written to private database - in this demo we are using sql-server-private.

```powershell
az container exec -n sqltools-private -g lapp --exec-command /bin/bash
sqlcmd -S 10.0.0.5 -d master -U sa -P "Azure12345678!" -Q "SELECT * FROM myTable"
exit
```

In portal stop Logic App now so we can try running it in different environments.

## Run Logic App in Kubernetes with serverles autoscaling using KEDA
Since Logic App is based on Azure Functions framework it can be packaged as Docker container and run in any environment. We will now combine Logic App with service bus trigger with deployment to any Kubernetes and scale-to-zero with KEDA. This allows for serverless behavior (no instance unless there are messages in queue) and scaling to multiple instances based on load (number of messages waiting). In our demo we will use AKS, but any Kubernetes running in eny environment or cloud would work.

### Build image
Make sure you have run Logic App locally before so code is compiled in bin folder.

We will use Azure Container Registry task to build and store Docker container with our Logic App.

```powershell
$registryName = (az deployment group show -n infra -g lapp --query properties.outputs.registryName.value -o tsv)
az acr build --image lapps/lapp:1.0 --registry $registryName .
```

### Create Kubernetes Secrets
Make sure you have kubectl, download credentials and create secret.

```powershell
# Get credentials
az aks get-credentials -n aks-lapp -g lapp --admin

# Storage connection string
$storageName = (az deployment group show -n infra -g lapp --query properties.outputs.storageName.value -o tsv)
$storageConnectionString = (az storage account show-connection-string -g lapp -n $storageName --query connectionString -o tsv)

# Service bus connection string
$serviceBusName = (az deployment group show -n infra -g lapp --query properties.outputs.serviceBusName.value -o tsv)
$serviceBusConnectionString = (az servicebus namespace authorization-rule keys list --namespace-name $serviceBusName -g lapp -n lappListener --query primaryConnectionString -o tsv)

# API endpoint
$apiEndpoint = (az container show -n httpbin-private -g lapp --query ipAddress.ip -o tsv)

# SQL conneciton string
$sqlIp = (az container show -n sql-server-private -g lapp --query ipAddress.ip -o tsv)
$sqlConnectionString = "Server=$sqlIp;Database=master;User Id=sa;Password=Azure12345678!;"

# Gather office365 connection key from your local.settings.json
$connectorKey = "<yourConnectorKey>"

# Create secret
kubectl create secret generic lapp-secrets `
    --from-literal="api=$apiEndpoint" `
    --from-literal="storage=$storageConnectionString" `
    --from-literal="servicebus=$serviceBusConnectionString" `
    --from-literal="sql=$sqlConnectionString" `
    --from-literal="office365=$connectorKey" 
```

We are now ready to run Logic App in Kubernetes.

### Run in Kubernetes
We will use Helm to deploy single replica of Logic App.

```powershell
# Use Helm to run Deployment with single instance. Make sure to specify your office connector app setting name.
helm upgrade -i lapp-static .\helm\lapp-static --set registryName=$registryName --set officeConnectorSettingName=office365_1-connectionKey

# Make sure container is up and running
kubectl get pods

# Follow logs
kubectl logs -l app=lapp -f
```

While watching container logs go to Azure portal Service Bus and create message. You should see all actions being logged. You will also receive email and you can check private SQL server was updated.

```powershell
az container exec -n sqltools-private -g lapp --exec-command /bin/bash
sqlcmd -S 10.0.0.5 -d master -U sa -P "Azure12345678!" -Q "SELECT * FROM myTable"
exit
```

Let's now delete this Helm release so we can try different one with scale-to-zero capabilities.

```powershell
helm delete lapp-static
```

### Scale-to-zero and autoscaling with KEDA
First install KEDA - autoscaling and scale-to-zero solution.

```powershell
helm repo add kedacore https://kedacore.github.io/charts
helm repo update
kubectl create namespace keda
helm install keda kedacore/keda --namespace keda
```

Add another Kubernetes Secret for KEDA to read queue information.

```powershell
# Get queue connection string
$serviceBusName = (az deployment group show -n infra -g lapp --query properties.outputs.serviceBusName.value -o tsv)
$queueConnectionString = (az servicebus queue authorization-rule keys list --namespace-name $serviceBusName --queue-name lapp -g lapp -n keda --query primaryConnectionString -o tsv)

# Create secret
kubectl create secret generic keda-servicebus --from-literal="connectionstring=$queueConnectionString" 
```

Deploy Logic App with scaler.

```powershell
helm upgrade -i lapp-serverless .\helm\lapp-serverless --set registryName=$registryName --set officeConnectorSettingName=office365_1-connectionKey
```

Note at idle there are no Logic App replicas running. KEDA is monitoring service bus will create Locic App instance when needed. Watch Pods.

```powershell
kubectl get pods -w
```

Use Azure portal to send message and what KEDA creating instance of Logic App on the fly.

To stop receiving messages remove Helm release.


```powershell
helm delete lapp-serverless
```

# Pausing environment
You might want to keep resources deployed so you do not have to change configuration settings yet save some costs when demo is not used. 

```powershell
# Stop components
az container stop -g lapp -n httpbin-private
az container stop -g lapp -n httpbin-public
az container stop -g lapp -n sql-server-private
az container stop -g lapp -n sql-server-public
az container stop -g lapp -n sqltools-private

az extension add --name aks-preview
az aks stop -n aks-lapp -g lapp

# Start components
az container start -g lapp -n httpbin-private
az container start -g lapp -n httpbin-public
az container start -g lapp -n sql-server-private
az container start -g lapp -n sql-server-public
az container start -g lapp -n sqltools-private

az extension add --name aks-preview
az aks start -n aks-lapp -g lapp
```

# Clean up environment
To clean environment simply delete Resource Group.

```powershell
az group delete -n lapp -y
```