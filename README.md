# k3d-local-registry
When using Tilt with a [k3s](https://k3s.io/) cluster, we recommend using a local registry for faster image pushing and pulling.

This repo provides a script to help you set up your cluster (via [k3d](https://github.com/rancher/k3d/))
with a local image registry that Tilt can auto-detect, so you don't need to do any additional configuration,
and Tilt knows where to push/pull your images to/from.

## UPDATE

k3d v4.0 has a built-in local registry! If you're able to upgrade to v4.0, we
strongly recommend you use the built-in registry. You will no longer need this
script.

[K3d Local Registry Instructions](https://k3d.io/usage/guides/registries/#using-a-local-registry)

Tilt-team has worked with K3d team to ensure that the built-in registry supports all the same
auto-discovery features as this script.

## How to Try It

1) Install [k3d](https://github.com/rancher/k3d/) (note: these instructions require **k3d v1.x**)

2) Copy the [k3d-with-registry.sh](k3d-with-registry.sh) script somewhere on your path.

3) Create a cluster with `k3d-with-registry.sh`. Currently it uses the default registry name `registry.local` and default port `5000`.

```
k3d-with-registry.sh
```

4) Verify your registry:

```
docker pull nginx:latest
docker tag nginx:latest localhost:5000/nginx:latest
docker push localhost:5000/nginx:latest
```

Set your KUBECONFIG as specified in script output (e.g. `export KUBECONFIG="$(k3d get-kubeconfig --name='diffname')"`)
and try spinning up a pod that references an image in your registry:

```
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-test-registry
  labels:
    app: nginx-test-registry
spec:
  replicas: 1
  selector:
    matchLabels:
      app: nginx-test-registry
  template:
    metadata:
      labels:
        app: nginx-test-registry
    spec:
      containers:
      - name: nginx-test-registry
        image: registry.local:5000/nginx:latest
        ports:
        - containerPort: 80
EOF
```

Verify the pod spun up correct with: `kubectl get pods -l "app=nginx-test-registry"`

Congrats! You can now push images to `localhost:5000/xxx`, and reference them in your k8s YAML as `registry.local:5000/xxx`.

[Tilt](https://tilt.dev) will automatically detect the local registry created by this script,
and do the image tagging dance (as of Tilt v0.12.0). In your Tiltfle and in your K8s YAML, just
refer to the image as `my-image`, and Tilt will take care of prepending `localhost:5000` etc. as appropriate.

## See also

* More info on [using registries with k3d](https://github.com/rancher/k3d/blob/master/docs/registries.md)
* The [Tilt + local registries guide for Kind](https://github.com/windmilleng/kind-local), which employs a similar pattern

## License

Copyright 2020 Windmill Engineering

Licensed under [the Apache License, Version 2.0](LICENSE)
