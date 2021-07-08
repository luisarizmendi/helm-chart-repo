# Red Hat Helm Charts
This repository contains some example Helm charts

The repository has been configured to serve the static helm index and chart files

## Usage

```

$ helm repo add larizmen-charts https://github.com/luisarizmendi/helm-chart-repo
"larizmen-charts" has been added to your repositories

$ helm repo list
NAME           	URL                               
larizmen-charts	https://github.com/luisarizmendi/helm-chart-repo  

```


## How the repo was made

Simple, using Helm CLI:

- Creating the packages:

```
helm package <charts directory>
```

- Creating the index.html


```
helm repo index <packages directory>
```

...or just run the script ./create_packages.sh



## Creating the Helm repo in OpenShift

If you want to create a repo in OpenShift pointing to these charts, just create this object:

```
apiVersion: helm.openshift.io/v1beta1
kind: HelmChartRepository
metadata:
  name: larizmen-helm-repo
spec:
  name: Luis Arizmendi Helm Charts
  connectionConfig:
    url: https://raw.githubusercontent.com/luisarizmendi/helm-chart-repo/main/packages
```

## Subtrees

This repository includes subtrees for some Charts, if you are working and there are new commits in the subtree that you want to get, you would need to run a command like this (example for analysis-v0.1 Charts):

```
git subtree pull --prefix charts/analysis-v0.1/analysis https://github.com/luisarizmendi/analysis-helm main --squash
```
