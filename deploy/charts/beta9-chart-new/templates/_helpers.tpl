{{/*
Copyright Broadcom, Inc. All Rights Reserved.
SPDX-License-Identifier: APACHE-2.0
*/}}

{{/*
Return the proper gateway image name
*/}}
{{- define "beta9.gateway.image" -}}
{{ include "common.images.image" (dict "imageRoot" .Values.gateway.image "global" .Values.global) }}
{{- end -}}

{{/*
Return the proper worker image name
*/}}
{{- define "beta9.worker.image" -}}
{{ include "common.images.image" (dict "imageRoot" .Values.worker.image "global" .Values.global) }}
{{- end -}}

{{/*
Return the proper image name (for the init container volume-permissions image)
*/}}
{{- define "beta9.volumePermissions.image" -}}
{{- include "common.images.image" ( dict "imageRoot" .Values.defaultInitContainers.volumePermissions.image "global" .Values.global ) -}}
{{- end -}}

{{/*
Return the proper Docker Image Registry Secret Names
*/}}
{{- define "beta9.imagePullSecrets" -}}
{{- include "common.images.renderPullSecrets" (dict "images" (list .Values.gateway.image .Values.worker.image .Values.defaultInitContainers.volumePermissions.image) "context" $) -}}
{{- end -}}

{{/*
Create the name of the service account to use
*/}}
{{- define "beta9.serviceAccountName" -}}
{{- if .Values.serviceAccount.create -}}
    {{ default (include "common.names.fullname" .) .Values.serviceAccount.name }}
{{- else -}}
    {{ default "default" .Values.serviceAccount.name }}
{{- end -}}
{{- end -}}

{{/*
Return true if cert-manager required annotations for TLS signed certificates are set in the Ingress annotations
Ref: https://cert-manager.io/docs/usage/ingress/#supported-annotations
*/}}
{{- define "beta9.ingress.certManagerRequest" -}}
{{ if or (hasKey . "cert-manager.io/cluster-issuer") (hasKey . "cert-manager.io/issuer") }}
    {{- true -}}
{{- end -}}
{{- end -}}

{{/*
Compile all warnings into a single message.
*/}}
{{- define "beta9.validateValues" -}}
{{- $messages := list -}}
{{- $messages := append $messages (include "beta9.validateValues.database" .) -}}
{{- $messages := append $messages (include "beta9.validateValues.redis" .) -}}
{{- $messages := without $messages "" -}}
{{- $message := join "\n" $messages -}}

{{- if $message -}}
{{-   printf "\nVALUES VALIDATION:\n%s" $message -}}
{{- end -}}
{{- end -}}

{{/*
Validate database configuration
*/}}
{{- define "beta9.validateValues.database" -}}
{{- if and (not .Values.postgresql.enabled) (not .Values.externalDatabase.host) -}}
beta9: database
    You must enable PostgreSQL or provide an external database host.
{{- end -}}
{{- end -}}

{{/*
Validate redis configuration  
*/}}
{{- define "beta9.validateValues.redis" -}}
{{- if and (not .Values.redis.enabled) (not .Values.externalRedis.host) -}}
beta9: redis
    You must enable Redis or provide an external Redis host.
{{- end -}}
{{- end -}}

{{/*
Return the PostgreSQL service name
*/}}
{{- define "beta9.postgresql.serviceName" -}}
{{- if .Values.postgresql.enabled -}}
{{- printf "%s" (include "postgresql.v1.primary.fullname" .Subcharts.postgresql) -}}
{{- else -}}
{{- .Values.externalDatabase.host -}}
{{- end -}}
{{- end -}}

{{/*
Return the Redis service name
*/}}
{{- define "beta9.redis.serviceName" -}}
{{- if .Values.redis.enabled -}}
{{- printf "%s-master" (include "common.names.dependency.fullname" (dict "chartName" "redis" "chartValues" .Values.redis "context" $)) -}}
{{- else -}}
{{- .Values.externalRedis.host -}}
{{- end -}}
{{- end -}}

{{/*
Return the JuiceFS Redis service name
*/}}
{{- define "beta9.juicefs-redis.serviceName" -}}
{{- if index .Values "juicefs-redis" "enabled" -}}
{{- printf "%s-master" (include "common.names.dependency.fullname" (dict "chartName" "juicefs-redis" "chartValues" (index .Values "juicefs-redis") "context" $)) -}}
{{- end -}}
{{- end -}}

{{/*
Return the Minio service name
*/}}
{{- define "beta9.minio.serviceName" -}}
{{- if .Values.minio.enabled -}}
{{- printf "%s" (include "common.names.dependency.fullname" (dict "chartName" "minio" "chartValues" .Values.minio "context" $)) -}}
{{- end -}}
{{- end -}}
