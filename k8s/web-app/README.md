# Web App 배포 가이드

## 사전 준비

```bash
# 1. kubeconfig 설정 (1회만)
aws eks update-kubeconfig --name awaves-dev --region us-east-1

# 2. 노드 확인
kubectl get nodes
```

## ECR 이미지 빌드 & 푸시

```bash
# ECR 로그인
aws ecr get-login-password --region us-east-1 \
  | docker login --username AWS --password-stdin \
    107570140649.dkr.ecr.us-east-1.amazonaws.com

# 빌드 & 태그 & 푸시 (프로젝트 루트에서)
docker build -t awaves-dev-web-app .
docker tag awaves-dev-web-app:latest \
  107570140649.dkr.ecr.us-east-1.amazonaws.com/awaves-dev-web-app:latest
docker push \
  107570140649.dkr.ecr.us-east-1.amazonaws.com/awaves-dev-web-app:latest
```

## 배포

```bash
# infra/k8s/web-app/ 에서 실행
kubectl apply -f deployment.yaml
kubectl apply -f service.yaml
kubectl apply -f ingress.yaml
kubectl apply -f hpa.yaml

# 또는 한번에
kubectl apply -f .
```

## 확인

```bash
# Pod 상태
kubectl get pods -n awaves-dev

# ALB 주소 확인 (1~3분 소요)
kubectl get ingress -n awaves-dev

# 로그 확인
kubectl logs -n awaves-dev -l app=web-app --tail=50
```

## 이미지 업데이트 (재배포)

```bash
# 새 이미지 태그로 롤링 업데이트
kubectl set image deployment/web-app \
  web-app=107570140649.dkr.ecr.us-east-1.amazonaws.com/awaves-dev-web-app:<NEW_TAG> \
  -n awaves-dev

# 롤아웃 상태 확인
kubectl rollout status deployment/web-app -n awaves-dev
```

## 수정 포인트

| 파일 | 수정 항목 |
|------|-----------|
| `deployment.yaml` | `NEXT_PUBLIC_API_URL` — backend-api 배포 후 실제 URL로 변경 |
| `deployment.yaml` | `/api/health` — Next.js health check 엔드포인트 구현 필요 |
| `ingress.yaml` | HTTPS 적용 시 ACM 인증서 ARN 추가 |
