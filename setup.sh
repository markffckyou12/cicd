#!/bin/bash
# setup.sh - Automated GitOps Environment Initialization

set -e # Exit immediately if any command fails

# --- Configuration Variables ---
ARGOCD_NAMESPACE="argocd"
APP_NAME="webapp-delivery"
APP_NAMESPACE="default"

echo "================================================="
echo "🚀 Starting Automated GitOps Environment Setup 🚀"
echo "================================================="

# CRITICAL FIX: Ensure port 8080 is free before starting
echo "🧹 Cleaning up background processes and ports..."
# Find the PID using port 8080 and kill it silently
sudo lsof -t -i:8080 | xargs -r kill -9 || true
echo "   Port 8080 is now free."

# 1. Clean Up Previous Installation
echo "🧹 1. Cleaning up previous ArgoCD and application deployment..."
kubectl delete ns $ARGOCD_NAMESPACE --ignore-not-found --wait=false 

# --- Delete cluster-scoped resources ---
echo "   Deleting cluster-scoped ArgoCD resources (CRDs, ClusterRoles, and Bindings)..."
kubectl delete crd applications.argoproj.io --ignore-not-found
kubectl delete crd appprojects.argoproj.io --ignore-not-found
kubectl delete crd applicationsets.argoproj.io --ignore-not-found

kubectl delete ClusterRole argocd-application-controller --ignore-not-found
kubectl delete ClusterRoleBinding argocd-application-controller --ignore-not-found
kubectl delete ClusterRole argocd-server --ignore-not-found
kubectl delete ClusterRoleBinding argocd-server --ignore-not-found
# ---------------------------------------------------------------------

# CRITICAL FIX: Loop until the namespace is confirmed gone
echo "⏳ Waiting for old $ARGOCD_NAMESPACE namespace to fully terminate..."
while kubectl get ns $ARGOCD_NAMESPACE &> /dev/null; do
    echo "   Namespace still terminating. Waiting 5s..."
    sleep 5
done
echo "   Namespace $ARGOCD_NAMESPACE is gone."

# 2. Install ArgoCD CLI (Skipped if already installed)
if ! command -v argocd &> /dev/null
then
    echo "⬇️ 2. ArgoCD CLI not found. Installing latest stable version..."
    VERSION=$(curl --silent "https://api.github.com/repos/argoproj/argo-cd/releases/latest" | grep '"tag_name"' | sed -E 's/.*"([^"]+)".*/\1/')
    curl -sSL -o argocd-linux-amd64 "https://github.com/argoproj/argo-cd/releases/download/$VERSION/argocd-linux-amd64"
    sudo install -m 555 argocd-linux-amd64 /usr/local/bin/argocd
    rm argocd-linux-amd64
else
    echo "CLI 2. ArgoCD CLI is already installed."
fi

# 3. Install ArgoCD Server Components using Helm
echo "📦 3. Installing ArgoCD Server via Helm..."
helm repo add argo https://argoproj.github.io/argo-helm --force-update 
helm repo update
kubectl create namespace $ARGOCD_NAMESPACE --dry-run=client -o yaml | kubectl apply -f -
helm install argocd argo/argo-cd -n $ARGOCD_NAMESPACE --wait 

# CRITICAL FIX: Wait for ArgoCD Pods to be Ready
echo "⏳ Waiting for ArgoCD Application Controller to become ready..."
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=argocd-application-controller -n $ARGOCD_NAMESPACE --timeout=120s
echo "   ArgoCD Application Controller is ready."

# 4. Apply the Final Working Application Definition
echo "📄 4. Applying the final webapp-delivery Application CRD..."
kubectl apply -f argocd-app.yaml

# 5. Wait for the Web Application Deployment to Complete
echo "⏳ 5. Waiting for webapp-delivery synchronization to complete..."
sleep 5
kubectl wait --for=condition=Synced application $APP_NAME -n $ARGOCD_NAMESPACE --timeout=120s
echo "   Application sync completed. Pod should be running."

# 6. Start Port Forwarding (Access the app)
echo "🌐 6. Starting Port Forwarding to expose application on 8080 (Run in background)..."
kubectl port-forward service/my-gitops-app-svc 8080:80 -n $APP_NAMESPACE & 

echo "================================================="
echo "✅ Setup Complete!"
echo "Your entire GitOps environment is deployed and ready. 

[Image of the CI/CD pipeline flow diagram]
"
echo "================================================="