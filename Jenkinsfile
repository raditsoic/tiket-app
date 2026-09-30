// tiket-app pipeline: build -> push to the lab registry. On main it also
// rolls the cluster by committing the new image tag to Raditsoic/tiket-k8s
// (the GitOps repo) — ArgoCD deploys from there. SSH to cp is read-only
// verification (rollout wait + health curl) — see the k8s repo README, CI/CD.
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
        stage('Deploy to k3s (GitOps)') {
            when { branch 'main' }
            steps {
                withCredentials([
                    sshUserPrivateKey(credentialsId: 'tiket-manifests-deploy-key', keyFileVariable: 'GIT_KEY'),
                    file(credentialsId: 'tiket-deploy-key', variable: 'DEPLOY_KEY')
                ]) {
                    sh '''#!/usr/bin/env bash
set -euo pipefail
TAG=$(cat .image-tag)
export GIT_SSH_COMMAND="ssh -i $GIT_KEY -o IdentitiesOnly=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
rm -rf manifests
git clone --depth 1 git@github.com:Raditsoic/tiket-k8s.git manifests
cd manifests
git config user.email "jenkins@tiket.lab"
git config user.name "tiket-ci"
# Roll only the tag (image.tag); the registry prefix lives in values.yaml.
sed -i "s#tag: \".*\"#tag: \"$TAG\"#" tiket/values.yaml
grep -q "tag: \"$TAG\"" tiket/values.yaml
git commit -am "roll tiket-app to $TAG"
git push origin main
# The git push IS the deploy. Below is read-only verification: ArgoCD
# polls the repo (~3 min), so wait until the live Deployment carries the
# tag, then follow the rollout and check the entry point.
cp=host.docker.internal
ssh_opts=(-i "$DEPLOY_KEY" -o IdentitiesOnly=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null)
img=""
for i in $(seq 1 60); do
  img=$(ssh "${ssh_opts[@]}" -p 2210 root@"$cp" \
    "kubectl get deployment tiket-app -o jsonpath='{.spec.template.spec.containers[0].image}'")
  [ "${img##*:}" = "$TAG" ] && break
  sleep 10
done
[ "${img##*:}" = "$TAG" ] || { echo "deployment never picked up $TAG (ArgoCD sync timeout)"; exit 1; }
ssh "${ssh_opts[@]}" -p 2210 root@"$cp" \
  "kubectl rollout status deployment/tiket-app --timeout=300s"
ssh "${ssh_opts[@]}" -p 2210 root@"$cp" "curl -fsS http://127.0.0.1/version" \
  | grep -qF "$TAG" || { echo "/version did not report $TAG"; exit 1; }
echo "cluster rolled to $TAG (via ArgoCD)"
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
