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
* Deploy 3 instances of Operaton running on Java 21
  with `REST API` only enabled (that means no `Webapps` nor `Swagger UI` will be enabled).
* Use PostgreSQL as an external database (it assumes that the database `process-engine` is already created
  and the secret `operaton-postgresql-credentials` has the mandatory data `DB_USERNAME` and `DB_PASSWORD`).
* Set custom config for `readinessProbe` and checking an endpoint that queries the database
  so no traffic will be sent to the REST API if the engine pod is not able to access the database.

```yaml
# Custom values.yaml

general:
  fullnameOverride: operaton-rest
  replicaCount: 3

image:
  javaVersion: 21

operaton:
  webapps: false
  rest: true

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

For the `tomcat` and `wildfly` distributions, this starts a JPDA debug socket, exposed as container port `debug` (8000).
For the `operaton` distribution, it only enables Spring Boot's debug output.

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

### Distribution

Operaton Docker image comes in 3 distributions `operaton` (the Spring Boot based standalone distribution),
`tomcat`, and `wildfly` which are published on [Docker hub](https://hub.docker.com/u/operaton).
Select the distribution with:

```yaml
distribution: operaton  # or tomcat, wildfly
```

The distribution selects the default image repository `operaton/<distribution>` and the configuration
of the container. Not every feature is supported by every distribution:

| Feature                                    | `operaton` | `tomcat` | `wildfly` |
|--------------------------------------------|------------|----------|-----------|
| [Start options](#start-options)            | ✅          | ❌        | ❌         |
| [New web apps](#new-web-apps)              | ✅          | ✅        | ✅         |
| [Metrics](#metrics)                        | ❌          | ✅        | ✅         |
| JPDA debug socket (`general.debug`)        | ❌          | ✅        | ✅         |

**Please note**, when setting `image.repository` explicitly, `distribution` must match the distribution of that image.

### Image

Each distribution has different tags, check the list of
[supported tags/releases](https://github.com/operaton/operaton-docker?tab=readme-ov-file#supported-tagsreleases)
by Operaton docker project for more details.

The default image tag is the Operaton version the chart version is released for.

`repository` and `tag` use [`tpl`](https://helm.sh/docs/howto/charts_tips_and_tricks/#using-the-tpl-function) function, it allows you to do templating:

```yaml
image:
  tag: "{{ .Chart.Version }}"
```

#### Java version

The images are published for Java 17, 21 and 25 with a `-jdk<version>` tag suffix.
The chart uses Java 25 by default. Select another Java version with:

```yaml
image:
  javaVersion: 21  # appends "-jdk21" to the tag
```

Set `javaVersion: ""` to use the tag as is, e.g. for custom images without the suffix.
Images without suffix run on Java 17.

### Start options

The components of the `operaton` distribution are configured with:

```yaml
operaton:
  webapps: true     # Web apps (Cockpit, Tasklist, Admin) at /operaton/
  rest: true        # REST API at /engine-rest
  swaggerUi: false  # Swagger UI at /swaggerui/index.html
  example: false    # Invoice example application
  production: false # Use the configuration file configuration/production.yml
```

These values are translated to the [startup options](https://github.com/operaton/operaton-docker#startup-options)
of the image. Unlike the image, which enables all components when started without options,
the chart enables only the web apps and the REST API by default.

**Please note**, the REST API does not require authentication by default, which also applies to requests sent by the Swagger UI.

When `image.args` is set, it is passed to the container as is and the start options above are ignored.
Since `args` replace the command of the image, start with the start script:

```yaml
image:
  args: ['./operaton.sh', '--rest']
```

When disabling the web apps, adjust the probes, which check `/operaton/` by default.

### New web apps

Operaton 2.2.0 ships new web apps as a technical preview, which are disabled by default. Enable them with:

```yaml
webappsNeo:
  enabled: true
```

The new web apps are then served at `/`, the web apps at `/operaton/` stay available.
For the `tomcat` and `wildfly` distributions, the chart sets the environment variable `OPERATON_BPM_WEBAPP_NEO_ENABLED`,
for the `operaton` distribution the start option `--webapps-neo` (not when `image.args` is set).

**Please note**, with the `operaton` distribution 2.2.0, the Swagger UI is not reachable when the new web apps are enabled.

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

The metrics are provided by the Prometheus JMX exporter, which is only supported by the `tomcat` and `wildfly` distributions.
Enable Prometheus metrics for Operaton by setting the following in the values file:

```yaml
distribution: tomcat
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

### Security Contexts (SCC platforms)

On platforms that enforce Security Context Constraints (e.g. OpenShift/OKD), the required
`fsGroup` and `runAsUser` values are namespace-dependent and assigned by the platform — but
only when those fields are absent or `null`. To let the platform assign them, set:

```yaml
podSecurityContext:
  fsGroup: null
securityContext:
  runAsUser: null
```

These fields are nullable in the schema, so this validates without `--skip-schema-validation`.
