# Three-environment Microsoft Azure service stack

This Terraform root is the Azure version of the original AWS project. It
creates exactly three Azure Linux Virtual Machines named `dev`, `test`, and
`production`. Each VM runs the same complete 36-container catalog.

## Service inventory

Every VM runs:

- The original 30 Docker services: language runtimes, frameworks, databases,
  web servers, Open WebUI, Jupyter, Ganache/Remix, EMQX, WebXR, PocketBase,
  Portainer, and n8n.
- Six added services: AR, VR, TensorFlow Serving, Kong Gateway, Apache NiFi,
  and MediaMTX.

One shared Azure Function supplies Function-as-a-Service. The project therefore
contains 37 logical service types and, after deployment, 108 container
deployments plus one Function App.

| Service | Purpose | Host access |
|---|---|---|
| Python | Python 3.12 runtime workspace | container shell only |
| Node.js | Node.js 22 runtime workspace | container shell only |
| Java | Eclipse Temurin Java 21 runtime | container shell only |
| Go | Go 1.22 runtime workspace | container shell only |
| Ruby | Ruby 3.3 runtime workspace | container shell only |
| Django | Python web-framework environment | container network only |
| Flask | Lightweight Python web-framework environment | container network only |
| FastAPI | Python API-framework environment | container network only |
| Express | Node.js web-framework environment | container network only |
| Spring Boot | Java application-framework environment | container network only |
| .NET SDK | .NET 8 development environment | container shell only |
| Apache Spark | Distributed data-processing environment | container shell only |
| MySQL | Relational database | TCP 3306, VNet only |
| MariaDB | MySQL-compatible relational database | TCP 3307, VNet only |
| PostgreSQL | Relational database | TCP 5432, VNet only |
| MongoDB | Document database | TCP 27017, VNet only |
| Redis | In-memory cache/data store | TCP 6379, VNet only |
| Nginx | Web server | HTTP 8080, trusted CIDRs only |
| Apache HTTPD | Web server | HTTP 8081, trusted CIDRs only |
| Tomcat | Java servlet server | HTTP 8082, trusted CIDRs only |
| WildFly | Jakarta EE application server | HTTP 8083, trusted CIDRs only |
| Open WebUI | Browser UI for AI/chat integrations | HTTP 3000, trusted CIDRs only |
| Jupyter | Notebook environment | TCP 8888, VNet only |
| Ganache | Local Ethereum development chain | TCP 8545, VNet only |
| Remix IDE | Browser Solidity IDE | HTTP 8085, trusted CIDRs only |
| EMQX | MQTT broker and IoT dashboard | MQTT 1883 trusted; admin 18083 VNet only |
| WebXR | Static A-Frame/WebXR demonstration | HTTP 8090, trusted CIDRs only |
| PocketBase | Lightweight backend/database service | HTTP 8091, trusted CIDRs only |
| Portainer | Docker administration UI | TCP 9000, VNet only |
| n8n | Workflow and robotic-process automation | HTTP 5678, trusted CIDRs only |
| AR | Static augmented-reality landing endpoint | HTTP 8092 or Kong `/ar` |
| VR | Static virtual-reality landing endpoint | HTTP 8093 or Kong `/vr` |
| TensorFlow Serving | Serves the bundled prediction model | REST 8501 or Kong `/ai` |
| Kong Gateway | Routes AR, VR, AI, video, and FaaS APIs | HTTP 8000 |
| Apache NiFi | Data-flow management | HTTPS 8443 on localhost; use SSH tunnel |
| MediaMTX | RTSP, RTMP, HLS, and WebRTC media server | TCP/UDP media ports |
| Azure Function | Shared HTTP Function-as-a-Service endpoint | HTTPS `/api/faas` |

“Trusted CIDRs only” means the port opens only after
`public_service_allowed_cidrs` is configured. The five runtime containers and
most framework containers are development environments, not prebuilt public
applications.

## Azure layout

```text
Azure Resource Group
+-- VNet 10.42.0.0/16
    +-- dev subnet 10.42.10.0/24
    |   +-- dev VM: Standard_D8s_v5, Premium 150-GB OS disk
    +-- test subnet 10.42.20.0/24
    |   +-- test VM: Standard_D8s_v5, Premium 150-GB OS disk
    +-- production subnet 10.42.30.0/24
        +-- production VM: Standard_D16s_v5, Premium 300-GB OS disk

Shared Azure resources
+-- Network Security Group
+-- Linux App Service plan
+-- Python Azure Function
+-- Storage Account
+-- Log Analytics workspace
+-- Application Insights
```

The VM sizes are intentionally substantial because every machine runs
databases, JVM services, Spark, NiFi, TensorFlow, and the rest of the catalog
together.

## AWS-to-Azure conversion

| AWS implementation | Azure implementation |
|---|---|
| EC2 | Azure Linux Virtual Machine |
| VPC/subnet | VNet/subnet |
| Security Group | Network Security Group |
| Public IPv4/EIP | Standard static Public IP |
| EBS gp3 | Premium managed OS disk |
| IAM instance profile | System-assigned Managed Identity |
| SSM | Azure Run Command and optional restricted SSH |
| Lambda and Function URL | Linux Azure Function App |
| CloudWatch Logs | Application Insights for the Function; add Azure Monitor Agent/DCR for centralized VM logs |

The Docker service definitions, health checks, ports, models, volumes, static
pages, and Kong routes are unchanged except that `/faas` now targets the Azure
Function endpoint.

## State safety

The old AWS `terraform.tfstate` and `terraform.tfstate.backup` files are
intentionally preserved. Azure uses the separate path `azure.tfstate`, as
configured in `backend.tf`.

Initialize using:

```powershell
terraform init -reconfigure
```

Do not use `-migrate-state`: the AWS resource addresses must never be copied
into the Azure state.

## Azure authentication

Authenticate without putting Azure credentials in Terraform files:

```powershell
az login
az account set --subscription "YOUR_SUBSCRIPTION_ID"
$env:ARM_SUBSCRIPTION_ID = "YOUR_SUBSCRIPTION_ID"
```

The AzureRM provider can then use the signed-in Azure CLI session.

## Validate without deploying

These commands do not create Azure resources:

```powershell
terraform init -reconfigure
terraform fmt -recursive -check
terraform validate
terraform test
```

The repository test mocks Azure, Local, and Random resources and generates only
an ephemeral local TLS key. The Archive provider also rebuilds the ignored
Function ZIP locally. Its `apply` command does not contact Azure.

With valid Azure authentication, this command previews account changes but does
not deploy them:

```powershell
terraform plan
```

Stop after the plan if zero Azure charges are required.

## Billing warning

Do not run either of these commands unless a real, billable deployment has been
approved:

```powershell
terraform apply
terraform apply -auto-approve
```

A real apply creates three large VMs, Premium disks, three Standard public IP
addresses, an App Service plan, Storage Account, Log Analytics, Application
Insights, and an Azure Function App.

The default VM sizes request 32 DSv5-family vCPUs in one region. Confirm
subscription quota and regional capacity before an approved deployment.

Always inspect the plan. A change to rendered VM custom data can force VM
replacement, and the Docker volumes currently stored on that VM's OS disk can
be deleted with it.

## Network access

Public service access is disabled by default. Add only trusted public IP ranges
when browser/API access is needed:

```hcl
public_service_allowed_cidrs = ["203.0.113.10/32"]
```

Using `["0.0.0.0/0"]` is possible for a temporary demonstration, but it exposes
the listed service ports to the entire internet and is not recommended.

SSH is disabled by default. To enable it, set only trusted public IP ranges:

```hcl
admin_allowed_cidrs = ["203.0.113.10/32"]
```

Database, cache, Jupyter, Portainer, Ganache, EMQX administration, and NiFi
ports are not publicly allowed by the Network Security Group.

## Outputs

After an approved deployment:

```powershell
terraform output resource_group_name
terraform output environment_instance_ids
terraform output environment_public_ips
terraform output environment_service_urls
terraform output environment_run_commands
terraform output azure_function_url
terraform output -json environment_nifi_ssh_tunnels
```

NiFi binds to localhost on each VM. If restricted SSH is enabled, run the
corresponding tunnel command and browse to `https://localhost:8443/nifi`.

## Smoke tests

After allowing your trusted CIDR, replace `ENVIRONMENT_IP` with a value from
`environment_public_ips`:

```powershell
curl.exe http://ENVIRONMENT_IP:8092/healthz
curl.exe http://ENVIRONMENT_IP:8093/healthz
curl.exe http://ENVIRONMENT_IP:8000/ar/healthz
curl.exe -H "Content-Type: application/json" -d '{"instances":[1.0,2.0,5.0]}' http://ENVIRONMENT_IP:8501/v1/models/half_plus_two:predict
curl.exe "$(terraform output -raw azure_function_url)"
```

The AR/VR landing pages work over HTTP, but immersive browser WebXR requires a
trusted HTTPS origin (or localhost). Add a real domain and TLS endpoint before
using immersive sessions. MediaMTX `/live` URLs are examples; publish a stream
named `live` before reading them.

Use Azure Run Command to inspect `/var/log/devcloud-userdata.log`,
`/var/log/platform-userdata.log`, `/opt/platform/bootstrap-success`, and both
Docker Compose projects.

## Sensitive local files

Never share or commit:

- `terraform.tfvars`
- `terraform.tfstate*`
- `azure.tfstate*`
- `*.pem`
- generated Function ZIP packages

Terraform state and VM custom data can contain service credentials. A
production implementation should move these credentials to Azure Key Vault
before deployment.

## Before production use

This repository is suitable for the requested three-VM demonstration, but a
real production rollout should also:

- move local state to an encrypted, locked Azure Storage backend;
- put credentials in Azure Key Vault and use separate values per environment;
- isolate production networking more strongly from dev and test; and
- attach backed-up data disks instead of keeping persistent Docker volumes on
  replaceable OS disks.

VM provisioning and container startup are separate stages. Confirm both
`/opt/runtime/bootstrap-success` and `/opt/platform/bootstrap-success` with
Azure Run Command before treating an environment as ready. The runtime marker
confirms that all 30 core container processes started; platform health checks
and the TensorFlow probe provide stronger functional checks for the six added
containers.

Several original core image tags intentionally remain floating (`latest`,
`main`, or major-version tags) to preserve the source project. Pin tested image
digests before requiring byte-for-byte parity across future VM replacements.
