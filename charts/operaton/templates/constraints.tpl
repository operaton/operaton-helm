{{/*
A template to handel constraints.
*/}}

{{/*
Fail in case H2 database is used and replicaCount is more than "1".
*/}}
{{/*
Fail in case metrics are enabled for the operaton distribution, which does not support the Prometheus JMX exporter.
*/}}
{{- if and .Values.metrics.enabled (eq .Values.distribution "operaton") }}
    {{ fail "metrics.enabled is only supported by the distributions tomcat and wildfly."}}
{{- end }}

{{/*
Fail in case no component of the operaton distribution is enabled, the image would enable all of them otherwise.
*/}}
{{- if and (eq .Values.distribution "operaton") (not .Values.image.args) }}
{{- if not (or .Values.operaton.webapps .Values.operaton.rest .Values.operaton.swaggerUi .Values.operaton.example .Values.webappsNeo.enabled) }}
    {{ fail "At least one of operaton.webapps, operaton.rest, operaton.swaggerUi, operaton.example or webappsNeo.enabled must be enabled."}}
{{- end }}
{{- end }}

{{- if eq (include "operaton.h2DatabaseIsUsed" .) "true" }}
{{- if gt (.Values.general.replicaCount | int) 1 }}
    {{ fail "Deployment replicaCount cannot be more than 1 in case H2 database is used."}}
{{- end }}
{{- end }}
