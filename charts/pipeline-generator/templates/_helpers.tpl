{{- define "arguments.pipeline" }}
- name: project
  value: {{ .Values.configuration.projectName | quote }}
- name: author
  value: {{ .Values.configuration.author | quote }}
- name: email
  value: {{ .Values.configuration.email | quote }}
- name: repository
  value: {{ .Values.configuration.repository | quote }}
- name: branch
  value: {{ .Values.configuration.branch | quote }}
- name: commit
  value: {{ $.Values.configuration.commit | quote }}
- name: cloneDepth
  value: {{ $.Values.configuration.cloneDepth | quote }}
- name: shortCommit
  value: {{ .Values.configuration.shortCommit | quote }}
- name: type
  value: {{ .Values.configuration.type | quote }}
- name: pipeline
  value: {{ .Values.configuration.pipeline | quote }}
- name: tektonDashboardURL
  value: {{ .Values.configuration.tektonDashboardURL | quote }}
{{- end }}

{{- define "parameters.pipeline" }}
- name: project
- name: author
- name: email
- name: repository
- name: branch
- name: commit
- name: cloneDepth
- name: shortCommit
- name: type
- name: pipeline
- name: tektonDashboardURL
{{- end }}

{{- define "arguments.common" }}
- name: repository
  value: {{ .repository | quote }}
- name: branch
  value: {{ .branch | quote }}
- name: commit
  value: {{ .commit  | quote }}
- name: cloneDepth
  value: {{ .cloneDepth  | quote }}
- name: shortCommit
  value: {{ .shortCommit | quote }}
- name: gcsBucket
  value: {{ .gcsBucket | quote }}
- name: email
  value: {{ .email | quote }}
- name: author
  value: {{ .author | quote }}
{{- end }}

{{- define "parameters.common" }}
- name: repository
- name: branch
- name: commit
- name: cloneDepth
- name: shortCommit
- name: gcsBucket
- name: email
- name: author
- name: artifacts
- name: cache
{{- end }}

{{- define "burnup" }}
- name: burnup
  image: {{ $.Values.images.gsutil }}
  volumeMounts:
  {{- if $.Values.configuration.gitCredentialsSecret }}
  - name: git-credentials
    mountPath: /fc/git-credentials
  {{- end }}
  {{- if not $.Values.configuration.sharedDataWorkspace }}
  - name: workspace-data
    mountPath: /fc/workspace-data
  {{- end }}
  workingDir: "/fc/workspace-data"
  script: |
    #!/usr/bin/env sh
    set -eux

    if [ -d /fc/workspace-data/lost+found ]; then
      rm -rf /fc/workspace-data/lost+found
    fi

    {{- if $.Values.configuration.enableAutocloneRepo }}
    if [ -d /fc/git-credentials ]; then
      cp -R "/fc/git-credentials" /root/.ssh
      chmod 700 /root/.ssh
      chmod -R 400 /root/.ssh/*
    fi
    if [ ! "$(ls -A /fc/workspace-data)" ]; then
      git config --global --add safe.directory /fc/workspace-data && \
      git clone --depth $(params.cloneDepth) --no-tags -b $(params.branch) \
        $(params.repository) \
        /fc/workspace-data && \
      git reset --hard $(params.commit)
    fi
    {{- end }}
    
    {{- if $.Values.configuration.cacheEnabled }}
      if [ "$(params.cache)" != "" ]; then
        for cache in $(params.cache)
        do
          nameCache=${cache##*/}
          gsutil -q stat gs://$(params.gcsBucket)/$(params.repository)/cache-$nameCache.tar.gz && \
          gsutil cp gs://$(params.gcsBucket)/$(params.repository)/cache-$nameCache.tar.gz ./cache-$nameCache.tar.gz && \
          tar -xzvf cache-$nameCache.tar.gz && rm cache-$nameCache.tar.gz || true
        done
      fi
    {{- end }}

    {{- if $.Values.configuration.artifactsEnabled }}
        if [ "$(params.artifacts)" != "" ]; then
            for artifact in $(params.artifacts)
            do
                nameArtifact=${artifact##*/}
                gsutil -q stat gs://$(params.gcsBucket)/$(params.repository)/artifacts-$nameArtifact-$(params.commit).tar.gz && \
                gsutil cp gs://$(params.gcsBucket)/$(params.repository)/artifacts-$nameArtifact-$(params.commit).tar.gz ./artifacts-$nameArtifact-$(params.commit).tar.gz && \
                tar -xzvf artifacts-$nameArtifact-$(params.commit).tar.gz && rm artifacts-$nameArtifact-$(params.commit).tar.gz || true
            done
        fi
    {{- end }}
{{- end }}

{{- define "burndown" }}
- name: burndown
  image: {{ $.Values.images.gsutil }}
  volumeMounts:
  {{- if $.Values.configuration.gitCredentialsSecret }}
  - name: git-credentials
    mountPath: /fc/git-credentials
  {{- end }}
  {{- if not $.Values.configuration.sharedDataWorkspace }}
  - name: workspace-data
    mountPath: /fc/workspace-data
  {{- end }}
  workingDir: "/fc/workspace-data"
  script: |
    #!/usr/bin/env sh
    set -eu

    {{- if $.Values.configuration.artifactsEnabled }}
    if [ "$(params.artifacts)" != "" ]; then
      for artifact in $(params.artifacts)
      do
          nameArtifact=${artifact##*/}
          tar -czf ./artifacts-$nameArtifact-$(params.commit).tar.gz $artifact && \
          gsutil -m cp -Z ./artifacts-$nameArtifact-$(params.commit).tar.gz gs://$(params.gcsBucket)/$(params.repository)/artifacts-$nameArtifact-$(params.commit).tar.gz && \
          rm ./artifacts-$nameArtifact-$(params.commit).tar.gz
      done
    fi
    {{- end }}

    {{- if $.Values.configuration.cacheEnabled }}
    if [ "$(params.cache)" != "" ]; then
      for cache in $(params.cache)
      do
        nameCache=${cache##*/}
        tar -czf ./cache-$nameCache.tar.gz $cache && \
        gsutil -m cp -Z ./cache-$nameCache.tar.gz gs://$(params.gcsBucket)/$(params.repository)/cache-$nameCache.tar.gz && \
        rm ./cache-$nameCache.tar.gz
      done
    fi
    {{- end }}
{{- end }}

{{- define "pipeline.generator" }}
- name: run
  image: {{ $.Values.images.helm }}
  volumeMounts:
  {{- if $.Values.configuration.gitCredentialsSecret }}
  - name: git-credentials
    mountPath: /fc/git-credentials
  {{- end }}
  {{- if not $.Values.configuration.sharedDataWorkspace }}
  - name: workspace-data
    mountPath: /fc/workspace-data
  {{- end }}
  workingDir: "/fc/workspace-data"
  script: |
    #!/usr/bin/env sh
    set -ex

    if [ -f fc-pipelines.yaml ]; then
      PIPELINES_FILE=fc-pipelines.yaml
    elif [ -f fc-pipelines.yml ]; then
      PIPELINES_FILE=fc-pipelines.yml
    else
      echo "ERROR. The pipeline file does not exist."
      exit 1
    fi

    REGISTRY={{ .Values.charts.OCIRegistry }}
    IMAGE={{ .Values.charts.pipelineGenerator }}
    VERSION={{ $.Values.apiVersion }}

    export HELM_EXPERIMENTAL_OCI=1

    gcloud auth application-default print-access-token | \
      helm registry login -u oauth2accesstoken --password-stdin https://${REGISTRY}

    helm template $(params.projectName) oci://${IMAGE} --version ${VERSION} -f ${PIPELINES_FILE} \
      --set configuration.type="$(params.type)" \
      --set configuration.eventlistener="$(params.eventlistener)" \
      --set configuration.trigger="$(params.trigger)" \
      --set configuration.projectName="$(params.projectName)" \
      --set configuration.branch="$(params.branch)" \
      --set configuration.pipeline="$(params.pipeline)" \
      --set configuration.author="$(params.author)" \
      --set configuration.email="$(params.email)" \
      --set configuration.commit="$(params.commit)" \
      --set configuration.shortCommit="$(params.shortCommit)" \
      --set configuration.repository="$(params.repository)" | \
      kubectl create -f -

{{- end }}

{{- define "failed.status" }}
when:
- input: "$(tasks.status)"
  operator: in
  values:
  - "Failed"
  - "None"
{{- end }}

{{- define "success.status" }}
when:
- input: "$(tasks.status)"
  operator: in
  values:
  - "Succeeded"
{{- end }}

{{- define "sendmail" }}
when:
- input: "$(tasks.status)"
  operator: in
  values:
  - "Failed"
  - "None"
taskRef:
  name: {{ $.Values.configuration.sendmailTaksName }}
  kind: ClusterTask
params:
- name: server
  value: {{ $.Values.configuration.sendmailSecret }}
- name: subject
  value: {{ $.Values.configuration.sendmailSubject }}
- name: body
  value: |
    {{ $.Values.configuration.sendmailBody | nindent 10 }}
- name: sender
  value: "<{{ $.Values.configuration.sendmailSender }}>"
- name: recipients
  value: "<$(params.email)>"
{{- end }}
