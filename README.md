# operaton-helm
Helm Charts for Operaton

## How to install
### Add the Helm Chart Repository
To add the Helm chart repository for Operaton, run:  

```shell
helm repo add operaton https://operaton.github.io/operaton-helm/
```

### Verify the Repository
To confirm that the repository has been added successfully, list all available repositories:

```shell
helm repo list
```

### Update Helm Repositories
Fetch the latest available chart versions by updating your Helm repositories:

```shell
helm repo update
```

### List Available Operaton Versions

To check the available versions of the Operaton BPM chart, use the following command:

```shell
helm search repo operaton-bpm --devel
```

The output should be something like:

```
NAME                 	CHART VERSION	APP VERSION 	DESCRIPTION                                       
operaton/operaton-bpm	1.0.0 	1.0.0-beta-3	Community Helm chart for Operaton BPM (Engine, ...
```

Note: The `--devel` flag includes development versions in the search results. Without this flag, only stable versions will be listed.

### Install a Specific Version

To install a specific version from the list above, use:

```shell
helm install operaton operaton/operaton-bpm --version 1.0.0
```

In this example:

* The Operaton BPM chart will be installed under the release name `operaton`
* The version `1.0.0` will be used
* The installation will take place in the `default` namespace.

To install the chart in a specific namespace, add the `-n YOUR_NAMESPACE` flag:

```shell
helm install operaton operaton/operaton-bpm --version 1.0.0 -n YOUR_NAMESPACE
```

### Verify the Installation

```shell
helm list -A
```

You should be able to see your chart installed having the status `deployed` like below:

```
NAME                	NAMESPACE	REVISION	UPDATED                                	STATUS  	CHART                    	APP VERSION 
operaton	default  	1       	2025-02-24 13:57:37.690267136 +0100 CET	deployed	operaton-bpm-1.0.0	1.0.0-beta-3
```

### Uninstall the chart

To uninstall the chart, you can use the command below:

```shell
helm uninstall operaton
```

## Security
The default security settings for the container are configured under `securityContext` in `values.yaml`.
These settings are appropriate for using Operaton with an H2 database. For production use,
where an external database is used, consider enabling the setting `readOnlyRootFilesystem: true`
to ensure that the root file system of your container remains read-only.

## Performance and Resource Consumption
The configuration related to resource consumption (CPU and memory) can be found under `resources` in `values.yaml`.
The default settings allocate a minimum of 250 milli-CPU cores and 512Mi of memory, with a maximum limit of 1 CPU core
and 1Gi of memory per pod. This ensures fair resource usage within your cluster and prevents
a single pod from exhausting available resources.
With these settings, a new pod typically starts in around 20 seconds. If your cluster allows
for higher resource allocation, consider increasing the values under `limits` to enhance performance.

## Autoscaling
By default, autoscaling is disabled for this chart. However, it is highly recommended to enable
it for production use. The autoscaling settings can be found under `autoscaling` in `values.yaml`.
The current configuration scales up by adding a new instance when the average CPU usage
across existing instances exceeds 80%. Please note that autoscaling requires a minimum amount
of resources per pod, which can be defined under `resources.requests`.
