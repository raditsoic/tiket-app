// tiket-app pipeline: build -> push to the lab registry; main also rolls
// the container on web1/web2 over SSH (deploy.sh, same container config
// as the Ansible playbook).
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
        stage('Deploy to web VMs') {
            when { branch 'main' }
            steps {
                withCredentials([file(credentialsId: 'tiket-deploy-key', variable: 'DEPLOY_KEY')]) {
                    sh '''#!/usr/bin/env bash
set -euo pipefail
TAG=$(cat .image-tag)
chmod 600 "$DEPLOY_KEY"
for pair in 192.168.56.11:8081 192.168.56.12:8082; do
  host=${pair%%:*}
  port=${pair##*:}
  ssh -i "$DEPLOY_KEY" -o IdentitiesOnly=yes -o StrictHostKeyChecking=no \
      -o UserKnownHostsFile=/dev/null \
      "vagrant@$host" "sudo bash -s -- $TAG" < deploy.sh
  ok=0
  for i in $(seq 1 30); do
    if curl -fsS "http://host.docker.internal:$port/healthz" >/dev/null; then ok=1; break; fi
    sleep 2
  done
  [ "$ok" = 1 ] || { echo "health check failed on $host"; exit 1; }
  echo "$host healthy with $TAG"
done
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
