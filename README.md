# Docker Mendix Buildpack

이 프로젝트는 Mendix 애플리케이션을 Docker 이미지로 빌드하고 Google Kubernetes Engine (GKE)과 같은 컨테이너 오케스트레이션 플랫폼에 배포하기 위한 빌드팩입니다.

## 프로젝트 개요

*   Mendix `.mda` 파일을 Docker 이미지로 변환합니다.
*   Google Cloud Build를 사용하여 빌드 프로세스를 자동화합니다.
*   빌드된 이미지를 Google Container Registry (GCR)에 푸시합니다.
*   Kubernetes 매니페스트를 사용하여 GKE에 애플리케이션을 배포합니다.

## 사전 요구 사항

이 프로젝트를 사용하려면 다음 도구들이 설치되어 있어야 합니다:

*   [Docker](https://www.docker.com/get-started)
*   [Google Cloud SDK (gcloud CLI)](https://cloud.google.com/sdk/docs/install)
*   [kubectl](https://kubernetes.io/docs/tasks/tools/install-kubectl/)
*   Google Cloud Platform (GCP) 프로젝트 및 GKE 클러스터

## 사용 방법

### 1. Google Cloud Project ID 확인

Cloud Build 및 GKE 배포를 위해 현재 GCP 프로젝트 ID를 확인합니다.

```bash
gcloud config get-value project
```

### 2. Mendix 애플리케이션 준비

배포하려는 Mendix 애플리케이션의 `.mda` 파일을 프로젝트 루트 디렉토리에 준비합니다. 예시로 `test-project.mda` 파일이 포함되어 있습니다.

### 3. Cloud Build를 통한 빌드 및 배포

`cloudbuild.yaml` 파일은 Mendix 애플리케이션을 빌드하고 GKE에 배포하는 전체 워크플로우를 정의합니다. 다음 명령어를 사용하여 Cloud Build를 실행합니다. **아래 명령어의 `$PROJECT_ID`, `_GKE_CLUSTER_NAME`, `_GKE_CLUSTER_REGION` 값은 사용자의 환경에 맞게 변경해야 합니다.**

```bash
gcloud builds submit . \
  --config=cloudbuild.yaml \
  --substitutions=_GKE_CLUSTER_NAME=YOUR_GKE_CLUSTER_NAME,_GKE_CLUSTER_REGION=YOUR_GKE_CLUSTER_REGION
```

*   `_GKE_CLUSTER_NAME`: 배포할 GKE 클러스터의 이름 (예: `mendix-cluster`)
*   `_GKE_CLUSTER_REGION`: GKE 클러스터가 위치한 리전 (예: `asia-south1`)
*   `$PROJECT_ID`: 사용자의 Google Cloud Project ID (위에서 확인한 값)


이 명령어는 다음 단계를 수행합니다:
1.  Mendix 빌드 환경을 위한 `mendix-rootfs:builder` Docker 이미지를 빌드합니다.
2.  Mendix 애플리케이션 실행을 위한 `mendix-rootfs:app` Docker 이미지를 빌드합니다.
3.  `build.py` 스크립트를 사용하여 `.mda` 파일을 `output-mda-dir`로 추출하고 필요한 빌드 파일을 생성합니다.
4.  최종 Mendix 애플리케이션 Docker 이미지를 빌드하고 GCR에 푸시합니다 (`gcr.io/$PROJECT_ID/mendix-app:latest`).
5.  `kubernetes/mendix-deployment.yaml` 및 `kubernetes/mendix-service.yaml` 파일을 사용하여 GKE 클러스터에 애플리케이션을 배포합니다.

### 4. Kubernetes 배포 상태 확인

배포가 성공적으로 완료되었는지 확인하려면 다음 `kubectl` 명령어를 사용합니다:

먼저 GKE 클러스터 인증 정보를 가져옵니다. **`mendix-cluster`, `asia-south1`, `$PROJECT_ID`는 사용자의 설정에 맞게 변경해야 합니다.**

```bash
gcloud container clusters get-credentials YOUR_GKE_CLUSTER_NAME --region YOUR_GKE_CLUSTER_REGION --project YOUR_PROJECT_ID
```

배포 및 파드 상태 확인:

```bash
kubectl get deployments
kubectl get pods
```

서비스 외부 IP 확인 (애플리케이션 접근을 위해):

```bash
kubectl get services
```

`mendix-service`의 `EXTERNAL-IP`를 통해 배포된 Mendix 애플리케이션에 접근할 수 있습니다.

### 5. 환경 변수 설정 및 Secret 관리

Mendix 애플리케이션은 데이터베이스 연결 정보, 관리자 비밀번호 등 다양한 환경 변수를 필요로 합니다. 민감한 정보를 코드에 직접 노출하는 대신, Kubernetes Secret을 사용하여 안전하게 관리하는 것이 권장됩니다.

`kubernetes/mendix-deployment.yaml` 파일은 이제 `mendix-db-secret`이라는 Secret에서 환경 변수들을 참조하도록 설정되어 있습니다. 배포를 진행하기 전에 반드시 이 Secret을 생성해야 합니다.

**Secret 생성 방법:**

다음 `kubectl` 명령어를 사용하여 `mendix-db-secret`을 생성합니다. **`--from-literal` 뒤의 값들은 실제 사용하려는 데이터베이스 정보 및 Mendix 관리자 비밀번호로 변경해야 합니다.**

```bash
kubectl create secret generic mendix-db-secret \
  --from-literal=DATABASE_ENDPOINT="postgres://YOUR_DB_USER:YOUR_DB_PASSWORD@YOUR_DB_HOST:YOUR_DB_PORT/YOUR_DB_NAME" \
  --from-literal=DATABASE_USERNAME="YOUR_DB_USERNAME" \
  --from-literal=DATABASE_PASSWORD="YOUR_DB_PASSWORD" \
  --from-literal=ADMIN_PASSWORD="YOUR_MENDIX_ADMIN_PASSWORD"
```

**주의:** Secret을 생성하지 않고 배포를 업데이트하면 파드가 시작되지 않거나 `CrashLoopBackOff` 상태에 빠질 수 있습니다.

**Secret 생성 후 배포 업데이트:**

Secret을 생성한 후, 다음 명령어를 사용하여 `mendix-deployment.yaml` 파일을 클러스터에 적용하여 변경 사항을 반영합니다.

```bash
kubectl apply -f kubernetes/mendix-deployment.yaml
```

필요에 따라 ConfigMap을 사용하여 민감하지 않은 설정들을 관리할 수도 있습니다.
