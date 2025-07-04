```bash
# Prequisite
# Install Minikube
# Install Helm
# Install Istioctl

# Start K8s Cluster on Specific Version
minikube start --kubernetes-version=v1.33.1

# Delete K8s Cluster (if you need to cleanup later)
minikube delete

# Install istio
istioctl install -y

# install ArgoCD in k8s
helm install argocd argo/argo-cd --namespace argocd --create-namespace --set global.domain=argocd.minikube.local --set server.config.url=https://argocd.minikube.local --set server.ingress.enabled=false --set dex.enabled=false --set server.extraArgs[0]=--insecure

# for kustomize to work need to edit the config map and add this line kustomize.buildOptions: --enable-helm to the data section
kubectl edit cm argocd-cm -n argocd

# Deploy management services
kubectl apply -k environment/dev/overlays

# login with admin user and below token (as in documentation):
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 --decode
kubectl -n monitoring get secret kube-prometheus-stack-grafana -o jsonpath="{.data.admin-password}" | base64 --decode

#Create a Grafana K8s Secret for Kiali
kubectl get secret kube-prometheus-stack-grafana -n monitoring -o jsonpath='{.data.admin-password}' | base64 --decode > grafana-password.txt

kubectl create secret generic kiali-grafana-secret -n istio-system --from-literal=username=admin --from-file=password=grafana-password.txt

#Verify External-IP - URLS: grafana.minikube.local, kiali.minikube.local, prometheus.minikube.local
kubectl get svc istio-ingressgateway -n istio-system
minikube tunnel

# Port Forwarding to access UI
kubectl port-forward -n argocd svc/argocd-server 8443:443
kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090
kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 8080:80

# Minikube to access UI
minikube service -n argocd argocd-server
minikube service -n monitoring kube-prometheus-stack-prometheus
minikube service -n monitoring kube-prometheus-stack-grafana

#If Kiali hangs https://pre-v1-41.kiali.io/documentation/v1.39/installation-guide/#_known_problem_uninstall_hangs

```
</br>

#### Links

* Config repo: [https://gitlab.com/nanuchi/argocd-app-config](https://gitlab.com/nanuchi/argocd-app-config)

* Docker repo: [https://hub.docker.com/repository/docker/nanajanashia/argocd-app](https://hub.docker.com/repository/docker/nanajanashia/argocd-app)

* Install ArgoCD: [https://argo-cd.readthedocs.io/en/stable/getting_started/#1-install-argo-cd](https://argo-cd.readthedocs.io/en/stable/getting_started/#1-install-argo-cd)

* Login to ArgoCD: [https://argo-cd.readthedocs.io/en/stable/getting_started/#4-login-using-the-cli](https://argo-cd.readthedocs.io/en/stable/getting_started/#4-login-using-the-cli)

* ArgoCD Configuration: [https://argo-cd.readthedocs.io/en/stable/operator-manual/declarative-setup/](https://argo-cd.readthedocs.io/en/stable/operator-manual/declarative-setup/)

* Grafana dashboards - import these into Grafana
https://github.com/istio/istio/blob/master/manifests/addons/dashboards/istio-mesh-dashboard.gen.json
https://github.com/istio/istio/blob/master/manifests/addons/dashboards/istio-performance-dashboard.json
https://github.com/istio/istio/blob/master/manifests/addons/dashboards/istio-service-dashboard.json
https://github.com/istio/istio/blob/master/manifests/addons/dashboards/istio-workload-dashboard.json