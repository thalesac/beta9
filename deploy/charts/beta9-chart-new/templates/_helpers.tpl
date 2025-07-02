{{/*
Return the proper gateway image name
*/}}
{{- define "beta9.gateway.image" -}}
{{ include "common.images.image" (dict "imageRoot" .Values.gateway.image "global" .Values.global) }}
{{- end -}}

{{/*
Return the proper image name (for the init container volume-permissions image)
*/}}
{{- define "beta9.volumePermissions.image" -}}
{{- include "common.images.image" ( dict "imageRoot" .Values.defaultInitContainers.volumePermissions.image "global" .Values.global ) -}}
{{- end -}}

{{/*
Return the proper image name (for the init container wait-on-backends image)
*/}}
{{- define "beta9.waitOnBackends.image" -}}
{{- include "common.images.image" ( dict "imageRoot" .Values.defaultInitContainers.waitOnBackends.image "global" .Values.global ) -}}
{{- end -}}

{{/*
Return the proper Docker Image Registry Secret Names
*/}}
{{- define "beta9.imagePullSecrets" -}}
{{- include "common.images.renderPullSecrets" (dict "images" (list .Values.gateway.image .Values.defaultInitContainers.volumePermissions.image .Values.defaultInitContainers.waitOnBackends.image) "context" $) -}}
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
{{- $messages := append $messages (include "beta9.validateValues.externalDatabase" .) -}}
{{- $messages := append $messages (include "beta9.validateValues.externalRedis" .) -}}
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
Validate external database configuration
*/}}
{{- define "beta9.validateValues.externalDatabase" -}}
{{- if and (not .Values.postgresql.enabled) .Values.externalDatabase.host -}}
  {{- if and .Values.externalDatabase.existingSecret (not .Values.externalDatabase.existingSecretPasswordKey) -}}
beta9: externalDatabase
    When using existingSecret, you must specify existingSecretPasswordKey.
  {{- end -}}
  {{- if and (not .Values.externalDatabase.existingSecret) (not .Values.externalDatabase.password) -}}
beta9: externalDatabase
    You must provide either password or existingSecret for external database.
  {{- end -}}
  {{- if not .Values.externalDatabase.user -}}
beta9: externalDatabase
    You must provide a user for external database.
  {{- end -}}
  {{- if not .Values.externalDatabase.database -}}
beta9: externalDatabase
    You must provide a database name for external database.
  {{- end -}}
{{- end -}}
{{- end -}}

{{/*
Validate external redis configuration
*/}}
{{- define "beta9.validateValues.externalRedis" -}}
{{- if and (not .Values.redis.enabled) .Values.externalRedis.host -}}
  {{- if and .Values.externalRedis.existingSecret (not .Values.externalRedis.existingSecretPasswordKey) -}}
beta9: externalRedis
    When using existingSecret, you must specify existingSecretPasswordKey.
  {{- end -}}
  {{- if and (not .Values.externalRedis.existingSecret) (not .Values.externalRedis.password) -}}
beta9: externalRedis
    You must provide either password or existingSecret for external Redis.
  {{- end -}}
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

{{/*
Get the external database password from secret or values
*/}}
{{- define "beta9.externalDatabase.password" -}}
{{- if .Values.externalDatabase.existingSecret -}}
{{- $secretKey := .Values.externalDatabase.existingSecretPasswordKey | default "password" -}}
{{- $secretObj := (lookup "v1" "Secret" .Release.Namespace .Values.externalDatabase.existingSecret) -}}
{{- if $secretObj -}}
{{- index $secretObj.data $secretKey | b64dec -}}
{{- else -}}
{{- printf "" -}}
{{- end -}}
{{- else -}}
{{- .Values.externalDatabase.password -}}
{{- end -}}
{{- end -}}

{{/*
Get the external redis password from secret or values
*/}}
{{- define "beta9.externalRedis.password" -}}
{{- if .Values.externalRedis.existingSecret -}}
{{- $secretKey := .Values.externalRedis.existingSecretPasswordKey | default "password" -}}
{{- $secretObj := (lookup "v1" "Secret" .Release.Namespace .Values.externalRedis.existingSecret) -}}
{{- if $secretObj -}}
{{- index $secretObj.data $secretKey | b64dec -}}
{{- else -}}
{{- printf "" -}}
{{- end -}}
{{- else -}}
{{- .Values.externalRedis.password -}}
{{- end -}}
{{- end -}}

{{/*
Build the complete Beta9 configuration with secret substitution
*/}}
{{- define "beta9.config" -}}
{{- $config := deepCopy .Values.config -}}
{{- if not .Values.postgresql.enabled -}}
  {{- if .Values.externalDatabase.host -}}
    {{- $_ := set $config.database.postgres "host" .Values.externalDatabase.host -}}
    {{- $_ := set $config.database.postgres "port" (.Values.externalDatabase.port | int) -}}
    {{- $_ := set $config.database.postgres "username" .Values.externalDatabase.user -}}
    {{- $_ := set $config.database.postgres "password" (include "beta9.externalDatabase.password" .) -}}
    {{- $_ := set $config.database.postgres "name" .Values.externalDatabase.database -}}
  {{- end -}}
{{- end -}}
{{- if not .Values.redis.enabled -}}
  {{- if .Values.externalRedis.host -}}
    {{- $_ := set $config.database.redis "addrs" (list (printf "%s:%d" .Values.externalRedis.host (.Values.externalRedis.port | int))) -}}
    {{- $_ := set $config.database.redis "password" (include "beta9.externalRedis.password" .) -}}
  {{- end -}}
{{- end -}}
{{- $config | toYaml -}}
{{- end -}}
