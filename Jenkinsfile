// tiket-app pipeline: build -> push to the lab registry; main also rolls
// the k3s Deployment on the lab cluster onto the exact build tag (kubectl
// set image + rollout status on lb over SSH — see the lb repo README, CI/CD).
pipeline {
    agent any
    stages {
        stage('Build image') {
            steps {
                sh 'echo "$(echo "$BRANCH_NAME" | tr "/" "-")-$BUILD_NUMBER" > .image-tag'
                sh 'docker build --build-arg APP_VERSION="$(cat .image-tag)" -t "localhost:5000/tiket-app:$(cat .image-tag)" .'
            }
        }
        stage('Push to registry') {
            steps {
                withCredentials([usernamePassword(credentialsId: 'tiket-registry',
                                                  usernameVariable: 'REG_USER',
                                                  passwordVariable: 'REG_PASS')]) {
                    sh '''#!/usr/bin/env bash
set -e
echo "$REG_PASS" | docker login localhost:5000 -u "$REG_USER" --password-stdin
docker push "localhost:5000/tiket-app:$(cat .image-tag)"
if [ "$BRANCH_NAME" = "main" ]; then
  docker tag "localhost:5000/tiket-app:$(cat .image-tag)" localhost:5000/tiket-app:latest
  docker push localhost:5000/tiket-app:latest
fi
'''
                }
            }
        }
        stage('Deploy to k3s') {
            when { branch 'main' }
            steps {
                withCredentials([file(credentialsId: 'tiket-deploy-key', variable: 'DEPLOY_KEY')]) {
                    sh '''#!/usr/bin/env bash
set -euo pipefail
TAG=$(cat .image-tag)
chmod 600 "$DEPLOY_KEY"
ssh_opts=(-i "$DEPLOY_KEY" -o IdentitiesOnly=yes -o StrictHostKeyChecking=no
          -o UserKnownHostsFile=/dev/null)
lb=host.docker.internal   # jenkins container -> host loopback -> NAT 2210 -> lb:22
# Image prefix (registry host) is read from the live Deployment so CI tracks
# lb's group_vars registry_host instead of duplicating it.
img=$(ssh "${ssh_opts[@]}" -p 2210 root@"$lb" \
  "kubectl get deployment tiket-app -o jsonpath='{.spec.template.spec.containers[0].image}'")
ssh "${ssh_opts[@]}" -p 2210 root@"$lb" \
  "kubectl set image deployment/tiket-app tiket-app=${img%:*}:$TAG"
ssh "${ssh_opts[@]}" -p 2210 root@"$lb" \
  "kubectl rollout status deployment/tiket-app --timeout=180s"
# Health through the real entry point (lb:80 = Traefik ingress). The jenkins
# container has no curl, so this runs on lb; /version serves APP_VERSION.
ssh "${ssh_opts[@]}" -p 2210 root@"$lb" "curl -fsS http://127.0.0.1/version" \
  | grep -qF "$TAG" || { echo "/version did not report $TAG"; exit 1; }
echo "cluster rolled to $TAG"
'''
                }
            }
        }
    }
    post {
        always {
            sh 'docker rmi -f "localhost:5000/tiket-app:$(cat .image-tag)" >/dev/null 2>&1 || true'
        }
    }
}
