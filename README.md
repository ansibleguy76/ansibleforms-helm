# AnsibleForms Helm Chart

This Helm chart deploys the AnsibleForms application and its MySQL database on Kubernetes. It is designed for flexibility, security, and ease of use in both development and production environments.

## Features

- Deploys AnsibleForms and MySQL with configurable images and resources
- Handles all sensitive data (DB credentials, admin credentials, encryption secret) via Kubernetes Secrets
- All application environment variables are configurable via `values.yaml`
- Storage class and size for both server and MySQL are configurable
- Supports both **dynamic provisioning** (StorageClass-based) and **pre-created static PVs**
- Ingress is optional and highly customizable (hostname, TLS, annotations, etc.)
- Service type (ClusterIP, LoadBalancer, NodePort) is configurable, with support for static LoadBalancer IPs
- (Optional) Support for managing `forms.yaml`, `forms/*.yaml` definitions, and `custom.js` via ConfigMaps

## Usage

### 1. Clone the Helm chart and values.yaml

```bash
git clone https://github.com/ansibleguy76/ansibleforms-helm
cp ./ansibleforms-helm/values.yaml my_values.yaml
```

### 2. Configure your values

Update the `my_values.yaml` to your taste.

#### Minimalistic example without ingress (dynamic storage with a StorageClass)

```yaml
application:
  server:
    env:
      HTTPS: 1 # auto sets port to 443
      ENCRYPTION_SECRET: "Abc123Abc123Abc123Abc123Abc123Abc1" # optional but recommended, 32 chars random string

storage:
  server:
    className: longhorn   # example dynamic StorageClass
    size: 5Gi
  mysql:
    className: longhorn
    size: 5Gi

service:
  server:
    type: LoadBalancer
    loadbalancer:
      ip: 10.0.0.1        # AnsibleForms will be available at https://10.0.0.1
```

#### Extended example with ingress

```yaml
application:
  server:
    env:
      HTTPS: 0 # auto sets ports on 80 or 443
      # ...other env vars (see values.yaml for all options)
      ENCRYPTION_SECRET: "Abc123Abc123Abc123Abc123Abc123Abc1"
      ADMIN_USERNAME: admin
      ADMIN_PASSWORD: MyAppPassword1!!
  mysql:
    user: root
    password: MyDbPassword1!!

storage:
  server:
    className: nfs-csi       # just an example storage provider
    size: 1Gi
  mysql:
    className: nfs-csi-nomap # just an example storage provider
    size: 1Gi

container:
  server:
    image: ansibleguy/ansibleforms:betav6
    resources:
      limits:
        cpu: "0.5"
        memory: 512Mi
      requests:
        cpu: "0.25"
        memory: 256Mi
  mysql:
    image: mysql:latest
    resources:
      limits:
        cpu: "0.5"
        memory: 512Mi
      requests:
        cpu: "0.25"
        memory: 256Mi

service:
  server:
    type: ClusterIP # service is exposed with ingress
  mysql:
    type: ClusterIP

ingress:
  enabled: true # enable ingress
  className: nginx
  hostname: ansibleforms.example.com
  path: /
  pathType: Prefix
  tls:
    enabled: true
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
    nginx.ingress.kubernetes.io/rewrite-target: /
  issuer: letsencrypt-prod
  extraHosts: [] # ["other.example.com"]
  extraPaths: [] # [{ path: /api, serviceName: server, servicePort: 80 }]
  extraAnnotations: {}
```

### 3. Storage configuration: dynamic provisioning vs static PVs

The chart supports two storage modes for both `server` and `mysql`:

1. **Dynamic provisioning (default)** – uses a Kubernetes StorageClass to dynamically provision PVs.
2. **Static PVs** – binds to pre-created PersistentVolumes by name.

#### 3.1 Dynamic provisioning (recommended for Longhorn / NFS-CSI, etc.)

Dynamic provisioning is the default mode. You typically configure:

```yaml
storage:
  server:
    className: longhorn   # or any other existing StorageClass
    size: 5Gi
    static:
      enabled: false
  mysql:
    className: longhorn
    size: 5Gi
    static:
      enabled: false
```

- If `storage.<component>.className` is set, the PVC will use that StorageClass.
- If `className` is omitted, the cluster's **default StorageClass** (if any) will be used.
- `static.enabled: false` (default) means **no `volumeName` is set**, so the cluster can bind the PVC to dynamically provisioned PVs.

#### 3.2 Static PVs (pre-created PersistentVolumes)

If you prefer to manage your own PersistentVolumes (for example, an NFS export or a hostPath PV), you can pre-create a PV and then tell the chart to bind to it.

Example: pre-create a static PV for MySQL:

```yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: ansibleforms-mysql-pv
spec:
  capacity:
    storage: 5Gi
  accessModes:
    - ReadWriteMany
  storageClassName: ""                     # empty for static binding
  persistentVolumeReclaimPolicy: Retain
  nfs:
    server: 10.0.0.10
    path: /exports/ansibleforms-mysql
```

Then configure the chart to use it:

```yaml
storage:
  mysql:
    size: 5Gi
    static:
      enabled: true
      volumeName: ansibleforms-mysql-pv    # must match the PV metadata.name
      storageClassName: ""                 # must match the PV storageClassName
```

When `static.enabled: true`:

- The PVC will include a `volumeName` (defaulting to `<release>-mysql-pv` / `<release>-server-pv` if `volumeName` is empty).
- The PVC will use `static.storageClassName` (or `""` if not provided).
- This binds the PVC directly to the specified pre-created PV.

You can configure the same pattern for the `server` volume:

```yaml
storage:
  server:
    size: 5Gi
    static:
      enabled: true
      volumeName: ansibleforms-server-pv
      storageClassName: ""
```

If you do **not** need static PVs, simply leave `static.enabled: false` and use the dynamic provisioning mode.

---

### 4. Using ConfigMaps for `forms.yaml`, form definitions, and `custom.js` (optional)

AnsibleForms uses a main configuration file (`forms.yaml`) and can also load additional form definitions from a `forms/` directory inside the persistent folder. It also supports a `custom.js` file for client-side customization, typically mounted at `/app/dist/src/functions/custom.js` as described in the AnsibleForms FAQ.

This chart provides optional values to mount those files from ConfigMaps:

```yaml
forms:
  configMap:
    enabled: true
    name: ansibleforms-forms                # ConfigMap containing the main forms.yaml
    key: forms.yaml                         # key in the ConfigMap
    mountPath: /app/dist/persistent/forms.yaml

  extraFormsConfigMap:
    enabled: true
    name: ansibleforms-forms-defs           # ConfigMap containing multiple form YAMLs
    mountPath: /app/dist/persistent/forms   # mounted as a directory

  customJs:
    enabled: true
    name: ansibleforms-custom-js            # ConfigMap containing custom.js
    key: custom.js                          # key in the ConfigMap
    mountPath: /app/dist/src/functions/custom.js
```

When any of the `enabled` flags are `false` (the default), the chart behaves as before and does not mount the corresponding ConfigMap.

#### 4.1 Example: main forms configuration (`forms.yaml`)

The following ConfigMap provides the main `forms.yaml` file, which defines categories, roles, and constants:

```yaml
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: ansibleforms-forms
  namespace: ansibleforms
data:
  forms.yaml: |
    categories:
      - name: Default
        icon: bars
      - name: Demo
        icon: heart
      - name: Maintenance
        icon: cogs
      - name: Internal
        icon: cogs
      - name: Vmware
        icon: cogs
    roles:
      - name: admin
        groups:
          - local/admins
          - ldap/k8admins
      - name: demo
        groups:
          - local/demo
      - name: public
        groups: []
      - name: internal
        groups:
          - ldap/internal
        users:
          - ldap/FRoca
    constants:
      AF_PLAYBOOKS: /app/dist/persistent/playbooks
```

With the `forms.configMap` values set as shown earlier, this `forms.yaml` will be mounted at `/app/dist/persistent/forms.yaml`, which is the default location used by AnsibleForms.

#### 4.2 Example: additional form definitions (`forms/*.yaml`)

You can keep each form definition in a separate YAML file within a second ConfigMap. Each key under `data:` becomes a file inside `/app/dist/persistent/forms/`:

```yaml
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: ansibleforms-forms-defs
  namespace: ansibleforms
data:
  awx-call-user_creation.yaml: |
    name: User Creation
    type: awx
    template: "jt-or_myawesomeor-create_user"
    roles:
      - internal
    categories:
      - Internal
    help: "Form to create FTP users"
    description: "Launch ftp user creation"
    fields:
      - name: survey_user
        label: Username
        type: text
        required: true
      - name: survey_password
        label: Password
        type: text
        required: true
      - name: survey_type
        label: Type
        type: enum
        values:
          - name: general
            value: general
          - name: av
            value: av
        required: true

  # more forms here, one per key:
  # otherform.yaml: |
  #   name: ...
  #   ...
```

#### 4.3 Example: `custom.js` for client-side customization

To inject a `custom.js` file into AnsibleForms, create a ConfigMap like:

```yaml
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: ansibleforms-custom-js
  namespace: ansibleforms
data:
  custom.js: |
    // Example custom JavaScript for AnsibleForms
    window.afCustom = window.afCustom || {};
    window.afCustom.onFormLoad = function (form) {
      console.log("Form loaded:", form.name);
    };
```

With `forms.customJs.enabled: true` and the values shown above, this file will be mounted at `/app/dist/src/functions/custom.js`, matching the location described in the AnsibleForms documentation.

### 5. Install the Chart

Depending on your environment, choose an existing namespace or choose to create a new one.

```bash
helm install ansibleforms ./ansibleforms-helm -f ./my_values.yaml -n ansibleforms --create-namespace
```

## Security Best Practices

- Use `--set` or `--set-file` to hide secrets
- Consider using external secret management solutions (Vault, SOPS, etc.) for highly sensitive data

## Customization

### Basic 

- All environment variables can be set in `env:`.
- All resource limits, storage, and service types are configurable.
- Ingress can be enabled/disabled and fully customized.
- Storage can be backed by dynamic StorageClasses or static PVs as needed.
- Forms configuration (`forms.yaml` and additional `forms/*.yaml`) and `custom.js` can be managed via ConfigMaps as shown above.

### Extras 1. Define extra volumes (root level) that you want to mount to containers.
```
extraVolumes:
  # ------------------------------------------------------------------------------
  # ADD HERE EXTRA VOLUME MOUNTS (if needed) (e.g CUSTOM CA CONFIGMAP or SECRET)
  # ------------------------------------------------------------------------------
  - name: ca-certs-configmap
    configMap:
      name: ca-certs-configmap
            
```

### Extras 2. Define extra volumes mounts that will be available to the server pod
```
containers:
  server:
    extraVolumeMounts:
      # ------------------------------------------------------------------
      # ENABLE THIS FOR CUSTOM CA CERTS (Must create configmap manually!)
      # ------------------------------------------------------------------
      - name: ca-certs-configmap
        mountPath: /etc/custom-certs/custom-ca.crt
        subPath: custom-ca.crt
        readOnly: true
            
```
### Extras 3. Define one or more init containers (e.g for changing the ownership of the specified directory)
```
containers:
  server:
    initContainers:
      - name: prepare-persistent-volume
        image: ansibleguy/ansibleforms:6.1.3-rc
        imagePullPolicy: IfNotPresent
        # This command changes the ownership of the specified directory.
        command: ["sh", "-c", "chown -R 1000:1000 /app/dist/persistent"]
        securityContext:
          # The container must run as the root user to have permission to chown.
          runAsUser: 0
        volumeMounts:
          - name: server-persistent-storage
            mountPath: /app/dist/persistent
```
### Extras 4. Configure extra environment variables
```
applications:
  server:
    env:
    # ******** UNCOMMENT TO IGNORE PRIVATE CA CERTS ********
    # NODE_TLS_REJECT_UNAUTHORIZED: 0

    # ******** UNCOMMENT THIS FOR PRIVATE CA CERTS ********
    # NODE_EXTRA_CA_CERTS: /etc/custom-certs/custom-ca.crt
```


### Extras 5. Other possible settings (other applications)
```
applications:
  mysql:
    password: <ENTER_PASSWORD_HERE>
    user: root
    # host: "mysql"   -> Setup custom mysql
    # port: "3306"    -> Setup custom mysql port
```


### Extras 5. Server Liveness and Readiness
#### Note: In case you face readiness issues or 503 Server errors after long api requests + big latency queries then increase the timeout value below.
```

containers:
  server:
    liveness:
      path: /
      initialDelaySeconds: 15
      periodSeconds: 15
      timeoutSeconds: 15
    readiness:
      path: /
      initialDelaySeconds: 15
      periodSeconds: 15
      timeoutSeconds: 15

```


## Notes

- Pods/services are named and discoverable by their service name within the namespace.
- For a full list of environment variables and their meanings, see the comments in `values.yaml` or visit the AnsibleForms documentation.
