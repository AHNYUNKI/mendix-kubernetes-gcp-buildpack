# Mendix 애플리케이션 GKE 배포 요약

이 문서는 Mendix 애플리케이션을 Google Kubernetes Engine (GKE)에 배포하는 과정을 요약합니다.

## 1. Google Cloud Project ID 확인

배포를 시작하기 전에 현재 Google Cloud Project ID를 확인했습니다.

```bash
gcloud config get-value project
```

확인된 Project ID: `electric-block-466106-k6`

## 2. Cloud Build 실행

`cloudbuild.yaml` 파일을 사용하여 Mendix 애플리케이션의 Docker 이미지를 빌드하고 Google Container Registry에 푸시하는 Cloud Build를 실행했습니다.

```bash
gcloud builds submit . --config=cloudbuild.yaml --substitutions=_GKE_CLUSTER_NAME=mendix-cluster,_GKE_CLUSTER_REGION=asia-south1
```

**빌드 중 발생한 경고/오류:**
*   `pip`가 'install'이라는 요구 사항을 찾지 못하는 경고가 있었으나, 빌드 자체에는 영향을 미치지 않았습니다.
*   'root' 사용자로 `pip`를 실행하는 것에 대한 경고가 있었습니다.
*   Mendix 버전 10.24가 유지 관리되지 않는다는 정보 메시지가 있었습니다.

## 3. Kubernetes 배포 상태 초기 확인

Cloud Build 완료 후, GKE 클러스터 인증 정보를 가져와 `kubectl`을 설정하고 배포 상태를 확인했습니다.

```bash
gcloud container clusters get-credentials mendix-cluster --region asia-south1 --project electric-block-466106-k6
kubectl get deployments
kubectl get pods
```

**초기 확인 결과:**
*   `mendix-app` 배포는 `0/1` READY 상태였습니다.
*   파드는 `InvalidImageName` 상태로, 이미지 이름에 문제가 있음을 나타냈습니다.

## 4. `InvalidImageName` 오류 해결

`InvalidImageName` 오류의 원인은 `kubernetes/mendix-deployment.yaml` 파일 내의 이미지 경로에 `$PROJECT_ID` 변수가 실제 Project ID로 대체되지 않았기 때문이었습니다.

`mendix-deployment.yaml` 파일의 이미지 경로를 실제 Project ID로 직접 수정했습니다.

```yaml
# kubernetes/mendix-deployment.yaml (수정 전)
image: gcr.io/$PROJECT_ID/mendix-app:latest

# kubernetes/mendix-deployment.yaml (수정 후)
image: gcr.io/electric-block-466106-k6/mendix-app:latest
```

수정된 배포 파일을 쿠버네티스 클러스터에 다시 적용했습니다.

```bash
kubectl apply -f kubernetes/mendix-deployment.yaml
```

## 5. Kubernetes 배포 상태 재확인

수정된 배포 파일을 적용한 후, 파드 상태를 다시 확인했습니다.

```bash
kubectl get pods
```

**재확인 결과:**
*   새로운 파드가 `ContainerCreating` 상태로 생성되었습니다.
*   `kubectl describe pod` 및 `kubectl get events` 명령어를 통해 이미지가 성공적으로 풀링되고 컨테이너가 생성 및 시작되었음을 확인했습니다.

최종적으로 파드 상태를 확인했을 때, `mendix-app` 파드가 `1/1` READY, `Running` 상태로 전환되었음을 확인했습니다.

```bash
kubectl get pods
```

## 6. 서비스 외부 IP 확인

애플리케이션에 접근하기 위한 외부 IP 주소를 확인하기 위해 서비스 상태를 확인했습니다.

```bash
kubectl get services
```

**서비스 확인 결과:**
*   `mendix-service`가 `LoadBalancer` 타입으로 외부 IP 주소 `34.100.142.209`를 할당받았습니다.

## 결론

Mendix 애플리케이션이 Google Kubernetes Engine (GKE) 클러스터에 성공적으로 배포되었습니다.

이제 웹 브라우저에서 다음 주소를 통해 애플리케이션에 접근할 수 있습니다:
[http://34.100.142.209](http://34.100.142.209)
