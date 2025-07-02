
{{/* vim: set filetype=mustache: */}}

{{/*
Returns an init-container that changes the owner and group of the persistent volume(s) mountpoint(s) to 'runAsUser:fsGroup' on each node
*/}}
{{- define "beta9.defaultInitContainers.volumePermissions" -}}
{{- $componentValues := index .context.Values .component -}}
- name: volume-permissions
  image: {{ include "beta9.volumePermissions.image" . }}
  imagePullPolicy: {{ .context.Values.defaultInitContainers.volumePermissions.image.pullPolicy | quote }}
  {{- if .context.Values.defaultInitContainers.volumePermissions.containerSecurityContext.enabled }}
  securityContext: {{- include "common.compatibility.renderSecurityContext" (dict "secContext" .context.Values.defaultInitContainers.volumePermissions.containerSecurityContext "context" .context) | nindent 4 }}
  {{- end }}
  {{- if .context.Values.defaultInitContainers.volumePermissions.resources }}
  resources: {{- toYaml .context.Values.defaultInitContainers.volumePermissions.resources | nindent 4 }}
  {{- else if ne .context.Values.defaultInitContainers.volumePermissions.resourcesPreset "none" }}
  resources: {{- include "common.resources.preset" (dict "type" .context.Values.defaultInitContainers.volumePermissions.resourcesPreset) | nindent 4 }}
  {{- end }}
  command:
    - /bin/bash
  args:
    - -ec
    - |
      mkdir -p {{ .context.Values.persistence.mountPath }}
      {{- if eq ( toString ( .context.Values.defaultInitContainers.volumePermissions.containerSecurityContext.runAsUser )) "auto" }}
      find {{ .context.Values.persistence.mountPath }} -mindepth 1 -maxdepth 1 -not -name ".snapshot" -not -name "lost+found" |  xargs -r chown -R $(id -u):$(id -G | cut -d " " -f2)
      {{- else }}
      find {{ .context.Values.persistence.mountPath }} -mindepth 1 -maxdepth 1 -not -name ".snapshot" -not -name "lost+found" |  xargs -r chown -R {{ $componentValues.containerSecurityContext.runAsUser }}:{{ $componentValues.podSecurityContext.fsGroup }}
      {{- end }}
  volumeMounts:
    - name: data
      mountPath: {{ .context.Values.persistence.mountPath }}
      {{- if .context.Values.persistence.subPath }}
      subPath: {{ .context.Values.persistence.subPath }}
      {{- end }}
{{- end -}}

{{/*
Returns an init-container that waits for backend services to be ready
*/}}
{{- define "beta9.initContainers.waitOnBackends" -}}
- name: wait-on-backends
  image: {{ include "beta9.waitOnBackends.image" . }}
  imagePullPolicy: {{ .Values.defaultInitContainers.waitOnBackends.image.pullPolicy | quote }}
  command:
    - sh
    - -c
    - |
      until nc -z {{ include "beta9.postgresql.serviceName" . }} 5432; do echo "Waiting on PostgreSQL..."; sleep 2; done;
      until nc -z {{ include "beta9.redis.serviceName" . }} 6379; do echo "Waiting on Redis..."; sleep 2; done;
      {{- if index .Values "juicefs-redis" "enabled" }}
      until nc -z {{ include "beta9.juicefs-redis.serviceName" . }} 6379; do echo "Waiting on Redis (JuiceFS)..."; sleep 2; done;
      {{- end }}
      {{- if .Values.minio.enabled }}
      until nc -z {{ include "beta9.minio.serviceName" . }} 9000; do echo "Waiting on Minio..."; sleep 2; done;
      {{- end }}
      echo "All systems ready!"
  volumeMounts:
    - name: config
      mountPath: /etc/beta9.d/config.yaml
      readOnly: true
      subPath: config.yaml
    - name: data
      mountPath: {{ .Values.persistence.mountPath }}
      {{- if .Values.persistence.subPath }}
      subPath: {{ .Values.persistence.subPath }}
      {{- end }}
{{- end -}}
