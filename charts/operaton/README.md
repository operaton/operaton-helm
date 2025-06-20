# Operaton Helm Chart

![Community Extension](https://img.shields.io/badge/Community%20Extension-An%20open%20source%20community%20maintained%20project-FF4700)
[![Forum](https://img.shields.io/badge/forum-Operaton-green)](https://forum.operaton.org/)
[![operaton manual latest](https://img.shields.io/badge/manual-latest-brown.svg)](https://docs.operaton.org/)
[![License](https://img.shields.io/github/license/operaton/operaton?color=blue&logo=apache)](https://github.com/operaton/operaton/blob/main/LICENSE)
[![Slack](https://img.shields.io/badge/chat-Slack-purple)](https://join.slack.com/t/operaton/shared_invite/zt-318m7owls-LPONm~7RUPw9I5m00hwAiw)

A Helm chart for Operaton, the open-source BPM engine.

## Install

```sh
helm repo add operaton https://operaton.github.io/operaton-helm/
helm repo update
helm install operaton operaton/operaton
```

## Links

* Operaton homepage: <https://operaton.org>
* Operaton Git repository: <https://github.com/operaton/operaton>
* Operaton Docker image: <https://github.com/operaton/operaton-docker>
* Operaton Forum: <https://forum.operaton.org/>

## Example

Using this custom values file the chart will:

* Use a custom name for deployment.
* Deploy 3 instances of Operaton
  with `REST API` only enabled (that means no `Webapps` nor `Swagger UI` will be enabled).
* Use PostgreSQL as an external database (it assumes that the database `process-engine` is already created
  and the secret `operaton-postgresql-credentials` has the mandatory data `DB_USERNAME` and `DB_PASSWORD`).
* Set custom config for `readinessProbe` and checking an endpoint that queries the database
  so no traffic will be sent to the REST API if the engine pod is not able to access the database.
* Expose Prometheus metrics of the Operaton over the metrics service with port `9404`.

```yaml
# Custom values.yaml

general:
  fullnameOverride: operaton-rest
  replicaCount: 3

image:
  name: operaton/operaton
  tag: 1.0.0-beta-4
  command: ['./operaton.sh']
  args: ['--rest']

extraEnvs:
- name: DB_VALIDATE_ON_BORROW
  value: "false"

database:
  driver: org.postgresql.Driver
  url: jdbc:postgresql://operaton-postgresql:5432/process-engine
  credentialsSecretName: operaton-postgresql-credentials
  credentialsSecretEnabled: true

service:
  type: ClusterIP
  port: 8080
  portName: http

readinessProbe:
  enabled: true
  config:
    httpGet:
      path: /engine-rest/incident/count
      port: http
    initialDelaySeconds: 120
    periodSeconds: 60

metrics:
  enabled: true
  service:
    type: ClusterIP
    port: 9404
    portName: metrics
    annotations:
      prometheus.io/scrape: "true"
      prometheus.io/path: "/"
      prometheus.io/port: "9404"
```

## Configuration

### General

#### Replicas

Set the number of replicas:

```yaml
general:
  replicaCount: 1
```

**Please note**, Operaton cluster mode is not supported with the default database H2,
and an external database should be used if you want to increase the number of the replicas.

#### Extra environment variables

The deployment could be customized by providing extra environment variables according to the project
[Docker image](https://github.com/operaton/operaton-docker). The extra environment variables will be templated using the ['tpl' function](https://helm.sh/docs/howto/charts_tips_and_tricks/#using-the-tpl-function). This is useful to pass a template string as a value to a chart or render external configuration files.

```yaml
extraEnvs:
- name: DB_VALIDATE_ON_BORROW
  value: "false"
- name: SERVICE_PORT
  value: {{ .Values.service.port }}
```

#### Debugging

Enable debugging in the Operaton container by setting:

```yaml
general:
  debug: true
```

### Init Containers

For a reason or another, you could need to do some pre-startup actions before the start of Operaton.
e.g. you could wait for a specific service to be ready or to post to an external service.

If that's needed, it could be done as the following:

```yaml
initContainers:
- name: pre-startup-checks
  image: busybox:1.28
  command: ['sh', '-c', 'echo "The initContainers work as expected"']
```

### Extra Containers

It might be the case, that you wanted to add sidecar containers.
e.g. you could have a fluentd that check your logs or a vault that inject your db secrets.

In such cases, this can be achieved as the following:

```yaml
extraContainers:
- name: fluentd
  image: "fluentd"
  volumeMounts:
    - mountPath: /my_mounts/cribl-config
      name: config-storage
```

### Image

Operaton Docker image comes in 3 distributions `tomcat`, `wildfly`, and `operaton` which are published on [Docker hub](https://hub.docker.com/u/operaton).
Each distro has different tags, check the list of
[supported tags/releases](https://github.com/operaton/operaton-docker?tab=readme-ov-file#supported-tagsreleases)
by Operaton docker project for more details.

The default image used in the chart is `operaton/operaton`, currently with the tag `1.0.0-beta-4`.

`repository` and `tag` use [`tpl`](https://helm.sh/docs/howto/charts_tips_and_tricks/#using-the-tpl-function) function, it allows you to do templating:

```yaml
image:
  tag: "{{ .Chart.Version }}"
```

### Database

Operaton supports PostgreSQL, MySQL and H2 by default. Details about database configuration can be found [here](https://github.com/operaton/operaton-docker?tab=readme-ov-file#database-environment-variables).

The H2 database is used by default which works fine if you just want to test Operaton.
But since the database is embedded, only 1 deployment replica could be used.

For real-world workloads, an external database like PostgreSQL should be used.
The following is an example of using PostgreSQL as an external database.

First, assuming that you have a PostgreSQL system up and running with service and port
`operaton-postgresql:5432`, also the database `process-engine` is created and you have its credentials,
create a secret has database credentials which will be used later by Operaton deployment:

```sh
$ kubectl create secret generic                 \
    operaton-postgresql-credentials \
    --from-literal=DB_USERNAME=foo              \
    --from-literal=DB_PASSWORD=bar
```

Now, set the values to use the external database:

```yaml
database:
  driver: org.postgresql.Driver
  url: jdbc:postgresql://operaton-postgresql:5432/process-engine
  credentialsSecretName: operaton-postgresql-credentials
  credentialsSecretEnabled: true
  # The username and password keys could be customized to whatever used in the credentials secret.
  credentialsSecretKeys:
    username: DB_USERNAME
    password: DB_PASSWORD
```

**Please note**, this Helm chart doesn't manage any external database, it just uses what's configured.

For configuring and managing external databases, please consult the following charts:
- [PostgreSQL](https://artifacthub.io/packages/helm/bitnami/postgresql)
- [MySQL](https://artifacthub.io/packages/helm/bitnami/mysql)

### Metrics

Enable Prometheus metrics for Operaton by setting the following in the values file:

```yaml
metrics:
  enabled: true
  service:
    type: ClusterIP
    port: 9404
    portName: metrics
    annotations:
      prometheus.io/scrape: "true"
      prometheus.io/path: "/"
      prometheus.io/port: "9404"
```

If there is a Prometheus configured in the cluster, it will scrap the metrics service automatically.
Check the notes after the deployment for more details about the metrics endpoint.
